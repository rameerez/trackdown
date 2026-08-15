# frozen_string_literal: true

require 'timeout'
require_relative 'base_provider'
require_relative '../location_result'
require_relative '../database_fingerprint'

# Conditionally require MaxMind - this is an optional dependency
begin
  require 'maxmind/db'
  require 'connection_pool'
rescue LoadError
  # MaxMind gem not available - that's ok, other providers might be used
end

module Trackdown
  module Providers
    # Provider that uses MaxMind GeoLite2 database for IP geolocation
    # Requires the maxmind-db gem and a downloaded database file
    class MaxmindProvider < BaseProvider
      class TimeoutError < Trackdown::Error; end
      class DatabaseError < Trackdown::Error; end

      DatabaseReader = Struct.new(:reader, :fingerprint, keyword_init: true)
      DatabaseLookup = Struct.new(:record, :fingerprint, keyword_init: true)
      private_constant :DatabaseReader, :DatabaseLookup

      # MaxMind publishes the accuracy radius as the radius, in kilometres, within
      # which the address is likely to be, at a 67% confidence level:
      # https://support.maxmind.com/knowledge-base/articles/maxmind-geolocation-accuracy
      ACCURACY_RADIUS_CONFIDENCE_PERCENTAGE = 67

      @reader_pool = nil
      @pool_mutex = Mutex.new
      @database_fingerprint = nil
      @database_fingerprints = {}
      @fingerprint_mutex = Mutex.new

      class << self
        def provider_name
          :maxmind
        end

        def provider_source
          :maxmind_local_database
        end

        # Check if MaxMind database is available
        def available?(request: nil)
          return false unless maxmind_available?
          return false unless Trackdown.database_exists?

          true
        end

        # The fingerprint used by the most recent successful reader fetch. Results
        # do not read this global diagnostic: each one retains its reader-bound
        # fingerprint, so concurrent generations can never mix provenance.
        def database_fingerprint
          @fingerprint_mutex.synchronize { @database_fingerprint }
        end

        # Forget the open database. Call this after replacing the .mmdb file so the
        # next lookup opens the new one — Trackdown::DatabaseUpdater already does.
        def reset_database!
          # Let go of the pool rather than shutting it down: a lookup already in
          # flight must not fail because a refresh happened underneath it. Ruby
          # reclaims the old readers once the last lookup lets go of them.
          @pool_mutex.synchronize do
            @reader_pool = nil
            @fingerprint_mutex.synchronize do
              @database_fingerprint = nil
              @database_fingerprints = {}
            end
          end
          nil
        end

        # Locate IP using MaxMind database
        # @param ip [String] The IP address to locate
        # @param request [ActionDispatch::Request, nil] Not used by MaxMind provider
        # @return [LocationResult] The location information
        def locate(ip, request: nil)
          raise Trackdown::Error, "MaxMind database not found" unless Trackdown.database_exists?
          raise Trackdown::Error, "maxmind-db gem not installed. Add it to your Gemfile: gem 'maxmind-db'" unless maxmind_available?

          lookup = fetch_record(ip)
          record = lookup.record
          fingerprint = lookup.fingerprint
          provenance = database_provenance(fingerprint)

          # We looked, in this exact database, and this address simply isn't in it.
          return LocationResult.unavailable(:address_not_found, **provenance) if record.nil?

          country_code = extract_country_code(record)
          country_name = extract_country_name(record)
          city = extract_city(record)
          flag_emoji = get_emoji_flag(country_code)
          accuracy_radius = record&.dig('location', 'accuracy_radius')

          LocationResult.new(
            country_code, country_name, city, flag_emoji,
            region: extract_region(record),
            region_code: record&.dig('subdivisions', 0, 'iso_code'),
            continent: record&.dig('continent', 'code'),
            timezone: record&.dig('location', 'time_zone'),
            latitude: record&.dig('location', 'latitude'),
            longitude: record&.dig('location', 'longitude'),
            postal_code: record&.dig('postal', 'code'),
            metro_code: record&.dig('location', 'metro_code')&.to_s,
            accuracy_radius_in_kilometers: accuracy_radius,
            accuracy_radius_confidence_percentage: (ACCURACY_RADIUS_CONFIDENCE_PERCENTAGE if accuracy_radius),
            **provenance
          )
        end

        private

        # Which database answered, plus how to identify it. The digest is a lambda
        # so reading it stays optional: an ordinary lookup never re-reads the file.
        def database_provenance(fingerprint)
          {
            provider_name: provider_name,
            provider_source: provider_source,
            database_build_epoch: fingerprint&.build_epoch,
            database_sha256: (-> { fingerprint.sha256 } if fingerprint)
          }
        end

        def maxmind_available?
          defined?(MaxMind::DB)
        end

        def fetch_record(ip)
          Timeout.timeout(Trackdown.configuration.timeout) do
            reader_pool.with do |database_reader|
              record = database_reader.reader.get(ip)
              fingerprint = remember_database(database_reader.fingerprint)

              DatabaseLookup.new(record: record, fingerprint: fingerprint)
            end
          end
        rescue Timeout::Error
          raise TimeoutError, "MaxMind database lookup timed out after #{Trackdown.configuration.timeout} seconds"
        rescue Trackdown::Error => e
          raise e
        rescue StandardError => e
          Rails.logger.error("Error fetching IP data: #{e.message}") if defined?(Rails)
          raise DatabaseError, "Database error: #{e.message}"
        end

        def reader_pool
          return @reader_pool if @reader_pool

          @pool_mutex.synchronize do
            @reader_pool ||= ConnectionPool.new(
              size: Trackdown.configuration.pool_size,
              timeout: Trackdown.configuration.pool_timeout
            ) do
              open_database_reader
            end
          end
        end

        # Capture the file identity before MaxMind opens it, then bind that exact
        # identity to the reader for its whole lifetime. If the path changes while
        # the reader opens, its eventual digest is nil rather than a digest from a
        # different database generation.
        def open_database_reader
          path = Trackdown.configuration.database_path
          fingerprint = DatabaseFingerprint.new(path: path)
          reader = MaxMind::DB.new(path, mode: Trackdown.configuration.memory_mode)
          fingerprint = fingerprint.with_build_epoch(build_epoch_of(reader))

          DatabaseReader.new(reader: reader, fingerprint: canonical_fingerprint(fingerprint))
        end

        def remember_database(fingerprint)
          @fingerprint_mutex.synchronize { @database_fingerprint = fingerprint }
          fingerprint
        end

        # Reuse one lazy digest for every pooled reader that opened the same path,
        # file identity, and database build. Readers from different generations
        # always retain different fingerprint objects.
        def canonical_fingerprint(fingerprint)
          @fingerprint_mutex.synchronize do
            @database_fingerprints[fingerprint.cache_key] ||= fingerprint
          end
        end

        def build_epoch_of(reader)
          reader.metadata&.build_epoch
        rescue StandardError
          nil
        end

        def extract_country_code(record)
          record&.dig('country', 'iso_code')
        end

        def extract_country_name(record)
          record&.dig('country', 'names', 'en') ||
            (record&.dig('country', 'names')&.values&.first) ||
            LocationResult::UNKNOWN
        end

        def extract_city(record)
          record&.dig('city', 'names', 'en') ||
            (record&.dig('city', 'names')&.values&.first) ||
            LocationResult::UNKNOWN
        end

        def extract_region(record)
          record&.dig('subdivisions', 0, 'names', 'en') ||
            record&.dig('subdivisions', 0, 'names')&.values&.first
        end
      end
    end
  end
end
