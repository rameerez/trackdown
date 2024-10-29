# frozen_string_literal: true

require 'maxmind/db'
require 'connection_pool'
require_relative 'location_result'
require_relative 'ip_validator'

module Trackdown
  class IpLocator
    class TimeoutError < Trackdown::Error; end
    class DatabaseError < Trackdown::Error; end

    class << self
      def locate(ip)
        IpValidator.validate!(ip)

        if Trackdown.configuration.reject_private_ips? && IpValidator.private_ip?(ip)
          raise IpValidator::InvalidIpError, "Private IP addresses are not allowed"
        end

        record = fetch_record(ip)
        return LocationResult.new(nil, 'Unknown', 'Unknown', '🏳️') if record.nil?

        country_code = extract_country_code(record)
        country_name = extract_country_name(record)
        city = extract_city(record)
        flag_emoji = get_emoji_flag(country_code)

        LocationResult.new(country_code, country_name, city, flag_emoji)
      end

      private

      def fetch_record(ip)
        Trackdown.ensure_database_exists!

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
        @reader_pool ||= ConnectionPool.new(
          size: Trackdown.configuration.pool_size,
          timeout: Trackdown.configuration.pool_timeout
        ) do
          MaxMind::DB.new(
            Trackdown.configuration.database_path,
            mode: Trackdown.configuration.memory_mode
          )
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

      def get_emoji_flag(country_code)
        country_code ? country_code.tr('A-Z', "\u{1F1E6}-\u{1F1FF}") : "🏳️"
      end
    end
  end
end
