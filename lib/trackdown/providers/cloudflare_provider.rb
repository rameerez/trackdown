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
    # Exact header contract:
    # https://developers.cloudflare.com/fundamentals/reference/http-headers/
    # Exact origin-protection guidance:
    # https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/
    class CloudflareProvider < BaseProvider
      COUNTRY_HEADER = 'HTTP_CF_IPCOUNTRY'
      CITY_HEADER = 'HTTP_CF_IPCITY'
      REGION_HEADER = 'HTTP_CF_REGION'
      REGION_CODE_HEADER = 'HTTP_CF_REGION_CODE'
      LATITUDE_HEADER = 'HTTP_CF_IPLATITUDE'
      LONGITUDE_HEADER = 'HTTP_CF_IPLONGITUDE'
      TIMEZONE_HEADER = 'HTTP_CF_TIMEZONE'
      CONTINENT_HEADER = 'HTTP_CF_IPCONTINENT'
      METRO_CODE_HEADER = 'HTTP_CF_METRO_CODE'
      POSTAL_CODE_HEADER = 'HTTP_CF_POSTAL_CODE'

      # Special Cloudflare country codes. Neither one names a country, so a
      # result carrying one reports :provider_returned_unknown_country.
      UNKNOWN_CODE = 'XX'
      TOR_CODE = 'T1'

      class << self
        def provider_name
          :cloudflare
        end

        def provider_source
          :cloudflare_request_headers
        end

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
        def locate(_ip, request: nil)
          raise Trackdown::Error, "CloudflareProvider requires a request object with Cloudflare headers" unless request

          provenance = request_provenance(request)
          country_code = extract_country_code(request)

          # If no valid country code, return unknown
          if country_code.nil? || country_code == UNKNOWN_CODE
            return LocationResult.unavailable(:provider_returned_unknown_country, **provenance)
          end

          country_name = get_country_name(country_code)
          city = extract_city(request)
          flag_emoji = get_emoji_flag(country_code)

          LocationResult.new(
            country_code, country_name, city, flag_emoji,
            region: extract_header(request, REGION_HEADER),
            region_code: extract_header(request, REGION_CODE_HEADER),
            continent: extract_header(request, CONTINENT_HEADER),
            timezone: extract_header(request, TIMEZONE_HEADER),
            latitude: parse_coordinate(request.env[LATITUDE_HEADER]),
            longitude: parse_coordinate(request.env[LONGITUDE_HEADER]),
            postal_code: extract_header(request, POSTAL_CODE_HEADER),
            metro_code: extract_header(request, METRO_CODE_HEADER),
            # "T1" says the visitor came through Tor, which is precisely a country
            # Cloudflare could not determine. The code is kept, the claim is not.
            # Only Cloudflare's own two pseudo-codes are treated this way: a code
            # we simply haven't heard of (Kosovo's user-assigned "XK", say) is a
            # real answer, not an unresolved one.
            # https://developers.cloudflare.com/fundamentals/reference/http-headers/#cf-ipcountry
            unavailable_reason: (:provider_returned_unknown_country if country_code == TOR_CODE),
            **provenance
          )
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

        def extract_header(request, header)
          value = request.env[header]
          return nil if value.nil? || value.empty?

          value
        end

        def parse_coordinate(value)
          return nil if value.nil? || value.empty?

          Float(value)
        rescue ArgumentError, TypeError
          nil
        end
      end
    end
  end
end
