require 'maxmind/db'
require_relative 'location_result'

module Trackdown
  class IpLocator
    class << self
      def locate(ip)
        record = fetch_record(ip)
        country_code = extract_country_code(record)
        country_name = extract_country_name(record)
        city = extract_city(record)
        flag_emoji = get_emoji_flag(country_code)
        LocationResult.new(country_code, country_name, city, flag_emoji)
      end

      private

      def fetch_record(ip)
        Trackdown.ensure_database_exists!
        reader = MaxMind::DB.new(Trackdown.configuration.database_path, mode: MaxMind::DB::MODE_MEMORY)
        record = reader.get(ip)
        reader.close
        record
      rescue Trackdown::Error => e
        raise e
      rescue => e
        Rails.logger.error("Error fetching IP data: #{e.message}") if defined?(Rails)
        nil
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
