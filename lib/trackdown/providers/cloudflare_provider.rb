# frozen_string_literal: true

require_relative 'base_provider'
require_relative '../location_result'

module Trackdown
  module Providers
    # Provider that uses Cloudflare HTTP headers for IP geolocation
    # This is the fastest and most lightweight option when your app is behind Cloudflare
    #
    # Cloudflare must have "IP Geolocation" or "Add visitor location headers" enabled
    # in the dashboard under Network settings or via Managed Transforms
    class CloudflareProvider < BaseProvider
      COUNTRY_HEADER = 'HTTP_CF_IPCOUNTRY'
      CITY_HEADER = 'HTTP_CF_IPCITY'

      # Special Cloudflare country codes
      UNKNOWN_CODE = 'XX'
      TOR_CODE = 'T1'

      class << self
        # Check if Cloudflare headers are available in the request
        def available?(request: nil)
          return false unless request

          country_code = request.env[COUNTRY_HEADER]
          !country_code.nil? && !country_code.empty? && country_code != UNKNOWN_CODE
        end

        # Locate IP using Cloudflare headers
        # @param ip [String] The IP address (not used, as Cloudflare already resolved it)
        # @param request [ActionDispatch::Request] Rails request object with Cloudflare headers
        # @return [LocationResult] The location information
        def locate(ip, request: nil)
          raise Trackdown::Error, "CloudflareProvider requires a request object with Cloudflare headers" unless request

          country_code = extract_country_code(request)

          # If no valid country code, return unknown
          return LocationResult.new(nil, 'Unknown', 'Unknown', '🏳️') if country_code.nil? || country_code == UNKNOWN_CODE

          country_name = get_country_name(country_code)
          city = extract_city(request)
          flag_emoji = get_emoji_flag(country_code)

          LocationResult.new(country_code, country_name, city, flag_emoji)
        end

        private

        def extract_country_code(request)
          code = request.env[COUNTRY_HEADER]
          return nil if code.nil? || code.empty? || code == UNKNOWN_CODE

          code.upcase
        end

        def extract_city(request)
          city = request.env[CITY_HEADER]

          # Cloudflare city header might not always be present
          # It requires "Add visitor location headers" Managed Transform
          return 'Unknown' if city.nil? || city.empty?

          city
        end
      end
    end
  end
end
