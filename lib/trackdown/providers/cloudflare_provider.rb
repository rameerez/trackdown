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

      # Cloudflare's XX and T1 pseudo-codes do not name countries. Unicode also
      # defines ZZ as unknown/invalid territory, so none is treated as a country.
      # Cloudflare: https://developers.cloudflare.com/fundamentals/reference/http-headers/#cf-ipcountry
      # Unicode ZZ semantics:
      # https://www.unicode.org/reports/tr35/tr35-78/tr35.html#unicode_region_subtag_validity
      UNKNOWN_CODE = 'XX'
      UNKNOWN_OR_INVALID_TERRITORY_CODE = 'ZZ'
      TOR_CODE = 'T1'
      UNAVAILABLE_COUNTRY_CODES = [UNKNOWN_CODE, UNKNOWN_OR_INVALID_TERRITORY_CODE].freeze
      COUNTRY_CODE_PATTERN = /\A[A-Za-z]{2}\z/
      LATITUDE_RANGE = (-90.0..90.0)
      LONGITUDE_RANGE = (-180.0..180.0)

      private_constant :UNAVAILABLE_COUNTRY_CODES,
                       :COUNTRY_CODE_PATTERN,
                       :LATITUDE_RANGE,
                       :LONGITUDE_RANGE

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

          !extract_country_code(request).nil?
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
            latitude: parse_coordinate(request.env[LATITUDE_HEADER], range: LATITUDE_RANGE),
            longitude: parse_coordinate(request.env[LONGITUDE_HEADER], range: LONGITUDE_RANGE),
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
          return nil unless code.is_a?(String)

          normalized_code = code.upcase
          return nil if UNAVAILABLE_COUNTRY_CODES.include?(normalized_code)
          return normalized_code if normalized_code == TOR_CODE
          return nil unless COUNTRY_CODE_PATTERN.match?(code)

          normalized_code
        rescue StandardError
          nil
        end

        def extract_city(request)
          city = request.env[CITY_HEADER]

          # Cloudflare city header might not always be present
          # It requires "Add visitor location headers" Managed Transform
          return 'Unknown' unless city.is_a?(String)
          return 'Unknown' if city.empty?

          city
        end

        def extract_header(request, header)
          value = request.env[header]
          return nil unless value.is_a?(String)
          return nil if value.empty?

          value
        end
      end
    end
  end
end
