# frozen_string_literal: true

require 'countries'

module Trackdown
  module Providers
    class BaseProvider
      # Returns true if this provider can handle the given request/context
      def self.available?(request: nil)
        raise NotImplementedError, "#{self} must implement .available?"
      end

      # Locates the IP and returns a LocationResult
      # @param ip [String] The IP address to locate
      # @param request [ActionDispatch::Request, nil] Optional Rails request object for header access
      # @return [LocationResult] The location information
      def self.locate(ip, request: nil)
        raise NotImplementedError, "#{self} must implement .locate"
      end

      protected

      # Helper to get emoji flag from country code
      def self.get_emoji_flag(country_code)
        country_code ? country_code.tr('A-Z', "\u{1F1E6}-\u{1F1FF}") : "🏳️"
      end

      # Helper to extract country name from country code using countries gem
      def self.get_country_name(country_code)
        return 'Unknown' unless country_code

        country = ISO3166::Country.new(country_code)
        country&.iso_short_name || country&.name || 'Unknown'
      rescue StandardError
        'Unknown'
      end
    end
  end
end
