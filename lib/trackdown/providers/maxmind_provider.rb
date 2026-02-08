# frozen_string_literal: true

require 'timeout'
require_relative 'base_provider'
require_relative '../location_result'

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

      @@reader_pool = nil
      @@pool_mutex = Mutex.new

      class << self
        # Check if MaxMind database is available
        def available?(request: nil)
          return false unless maxmind_available?
          return false unless Trackdown.database_exists?

          true
        end

        # Locate IP using MaxMind database
        # @param ip [String] The IP address to locate
        # @param request [ActionDispatch::Request, nil] Not used by MaxMind provider
        # @return [LocationResult] The location information
        def locate(ip, request: nil)
          raise Trackdown::Error, "MaxMind database not found" unless Trackdown.database_exists?
          raise Trackdown::Error, "maxmind-db gem not installed. Add it to your Gemfile: gem 'maxmind-db'" unless maxmind_available?

          record = fetch_record(ip)
          return LocationResult.new(nil, 'Unknown', 'Unknown', '🏳️') if record.nil?

          country_code = extract_country_code(record)
          country_name = extract_country_name(record)
          city = extract_city(record)
          flag_emoji = get_emoji_flag(country_code)

          LocationResult.new(
            country_code, country_name, city, flag_emoji,
            region: extract_region(record),
            region_code: record&.dig('subdivisions', 0, 'iso_code'),
            continent: record&.dig('continent', 'code'),
            timezone: record&.dig('location', 'time_zone'),
            latitude: record&.dig('location', 'latitude'),
            longitude: record&.dig('location', 'longitude'),
            postal_code: record&.dig('postal', 'code'),
            metro_code: record&.dig('location', 'metro_code')&.to_s
          )
        end

        private

        def maxmind_available?
          defined?(MaxMind::DB)
        end

        def fetch_record(ip)
          Timeout.timeout(Trackdown.configuration.timeout) do
            reader_pool.with do |reader|
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

        def extract_country_code(record)
          record&.dig('country', 'iso_code')
        end

        def extract_country_name(record)
          record&.dig('country', 'names', 'en') ||
            (record&.dig('country', 'names')&.values&.first) ||
            'Unknown'
        end

        def extract_city(record)
          record&.dig('city', 'names', 'en') ||
            (record&.dig('city', 'names')&.values&.first) ||
            'Unknown'
        end

        def extract_region(record)
          record&.dig('subdivisions', 0, 'names', 'en') ||
            record&.dig('subdivisions', 0, 'names')&.values&.first
        end
      end
    end
  end
end
