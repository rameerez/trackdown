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

      # MaxMind publishes the accuracy radius as the radius, in kilometres, within
      # which the address is likely to be, at a 67% confidence level:
      # https://support.maxmind.com/knowledge-base/articles/maxmind-geolocation-accuracy
      ACCURACY_RADIUS_CONFIDENCE_PERCENTAGE = 67

      @@reader_pool = nil
      @@pool_mutex = Mutex.new
      @@database_fingerprint = nil
      @@fingerprint_mutex = Mutex.new

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

        # Which database is answering lookups, so a result can say where it came
        # from. Nil until the first lookup has actually opened a database.
        def database_fingerprint
          @@database_fingerprint
        end

        # Forget the open database. Call this after replacing the .mmdb file so the
        # next lookup opens the new one — Trackdown::DatabaseUpdater already does.
        def reset_database!
          # Let go of the pool rather than shutting it down: a lookup already in
          # flight must not fail because a refresh happened underneath it. Ruby
          # reclaims the old readers once the last lookup lets go of them.
          @@pool_mutex.synchronize { @@reader_pool = nil }
          @@fingerprint_mutex.synchronize { @@database_fingerprint = nil }
          nil
        end

        # Locate IP using MaxMind database
        # @param ip [String] The IP address to locate
        # @param request [ActionDispatch::Request, nil] Not used by MaxMind provider
        # @return [LocationResult] The location information
        def locate(ip, request: nil)
          raise Trackdown::Error, "MaxMind database not found" unless Trackdown.database_exists?
          raise Trackdown::Error, "maxmind-db gem not installed. Add it to your Gemfile: gem 'maxmind-db'" unless maxmind_available?

          record = fetch_record(ip)
          provenance = database_provenance

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
        def database_provenance
          fingerprint = @@database_fingerprint

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
            reader_pool.with do |reader|
              remember_database(reader)
              reader.get(ip)
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
          return @@reader_pool if @@reader_pool

          @@pool_mutex.synchronize do
            @@reader_pool ||= ConnectionPool.new(
              size: Trackdown.configuration.pool_size,
              timeout: Trackdown.configuration.pool_timeout
            ) do
              MaxMind::DB.new(
                Trackdown.configuration.database_path,
                mode: Trackdown.configuration.memory_mode
              )
            end
          end
        end

        # Note which database is answering, using the reader that is actually
        # serving this lookup — its own metadata is authoritative for the build date.
        #
        # Comparing that build date costs nothing (it's already in memory) and is
        # what keeps us honest: if the .mmdb was replaced on disk and this reader
        # opened the new one, we re-fingerprint instead of stamping results with
        # the previous database's date.
        def remember_database(reader)
          path = Trackdown.configuration.database_path
          build_epoch = build_epoch_of(reader)
          return if remembered?(path, build_epoch)

          @@fingerprint_mutex.synchronize do
            return if remembered?(path, build_epoch)

            @@database_fingerprint = DatabaseFingerprint.new(path: path, build_epoch: build_epoch)
          end
        end

        def remembered?(path, build_epoch)
          fingerprint = @@database_fingerprint

          !fingerprint.nil? && fingerprint.path == path && fingerprint.build_epoch == build_epoch
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
