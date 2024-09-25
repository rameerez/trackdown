require 'maxmind/db'

module Trackdown
  class IpLocator
    class << self
      def locate(ip)
        record = fetch_record(ip)
        {
          country_code: extract_country_code(record),
          city: extract_city(record),
          emoji_flag: get_emoji_flag(extract_country_code(record))
        }
      end

      private

      def fetch_record(ip)
        reader = MaxMind::DB.new(Trackdown.configuration.database_path, mode: MaxMind::DB::MODE_MEMORY)
        record = reader.get(ip)
        reader.close
        record
      rescue => e
        Rails.logger.error("Error fetching IP data: #{e.message}") if defined?(Rails)
        nil
      end

      def extract_country_code(record)
        record&.dig('country', 'iso_code')
      end

      def extract_city(record)
        record&.dig('city', 'names', 'en') ||
          (record&.dig('city', 'names')&.values&.first) ||
          'unknown'
      end

      def get_emoji_flag(country_code)
        country_code ? country_code.tr('A-Z', "\u{1F1E6}-\u{1F1FF}") : "❔"
      end
    end
  end
end
