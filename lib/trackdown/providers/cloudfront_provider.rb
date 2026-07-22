# frozen_string_literal: true

require_relative 'base_provider'
require_relative '../location_result'

module Trackdown
  module Providers
    # Provider that uses Amazon CloudFront HTTP headers for IP geolocation.
    # This is the fastest and most lightweight option when your app is behind
    # CloudFront (the AWS CDN) — a direct analog to the Cloudflare provider.
    #
    # CloudFront resolves the viewer's location at the edge and forwards it to the
    # origin as CloudFront-Viewer-* headers. To receive them, attach an origin
    # request policy that forwards the CloudFront geolocation headers — the AWS
    # managed policy "AllViewerAndCloudFrontHeaders-2022-06" includes all of them.
    # See: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-cloudfront-headers.html
    #
    # Note: CloudFront does not emit a continent header. We derive #continent from the
    # country code so it matches the 2-letter code (e.g. "NA") the other providers
    # return. The countries gem exposes a continent *name* ("North America") but no
    # code, and its names don't map by initials (Africa/Asia/Antarctica/Australia all
    # start with "A", and it labels Oceania "Australia"), so an explicit table is the
    # only reliable mapping.
    class CloudfrontProvider < BaseProvider
      # ISO3166 continent name (from the countries gem) => 2-letter code used by the
      # Cloudflare and MaxMind providers.
      CONTINENT_CODES = {
        'Africa' => 'AF',
        'Antarctica' => 'AN',
        'Asia' => 'AS',
        'Europe' => 'EU',
        'North America' => 'NA',
        'South America' => 'SA',
        'Australia' => 'OC' # the countries gem labels Oceania "Australia"
      }.freeze

      COUNTRY_HEADER = 'HTTP_CLOUDFRONT_VIEWER_COUNTRY'
      CITY_HEADER = 'HTTP_CLOUDFRONT_VIEWER_CITY'
      # CloudFront exposes both a region code ("CA") and its full name ("California").
      # Match the Cloudflare provider's semantics: #region is the name, #region_code the code.
      REGION_HEADER = 'HTTP_CLOUDFRONT_VIEWER_COUNTRY_REGION_NAME'
      REGION_CODE_HEADER = 'HTTP_CLOUDFRONT_VIEWER_COUNTRY_REGION'
      LATITUDE_HEADER = 'HTTP_CLOUDFRONT_VIEWER_LATITUDE'
      LONGITUDE_HEADER = 'HTTP_CLOUDFRONT_VIEWER_LONGITUDE'
      TIMEZONE_HEADER = 'HTTP_CLOUDFRONT_VIEWER_TIME_ZONE'
      POSTAL_CODE_HEADER = 'HTTP_CLOUDFRONT_VIEWER_POSTAL_CODE'
      METRO_CODE_HEADER = 'HTTP_CLOUDFRONT_VIEWER_METRO_CODE'

      class << self
        # Check if CloudFront headers are available in the request
        def available?(request: nil)
          return false unless request

          country_code = request.env[COUNTRY_HEADER]
          !country_code.nil? && !country_code.empty?
        end

        # Locate IP using CloudFront headers
        # @param ip [String] The IP address (not used, as CloudFront already resolved it)
        # @param request [ActionDispatch::Request] Rails request object with CloudFront headers
        # @return [LocationResult] The location information
        def locate(ip, request: nil)
          raise Trackdown::Error, "CloudfrontProvider requires a request object with CloudFront headers" unless request

          country_code = extract_country_code(request)

          # If no valid country code, return unknown
          return LocationResult.new(nil, 'Unknown', 'Unknown', '🏳️') if country_code.nil?

          country_name = get_country_name(country_code)
          city = extract_city(request)
          flag_emoji = get_emoji_flag(country_code)

          LocationResult.new(
            country_code, country_name, city, flag_emoji,
            region: extract_header(request, REGION_HEADER),
            region_code: extract_header(request, REGION_CODE_HEADER),
            continent: continent_code(country_code),
            timezone: extract_header(request, TIMEZONE_HEADER),
            latitude: parse_coordinate(request.env[LATITUDE_HEADER]),
            longitude: parse_coordinate(request.env[LONGITUDE_HEADER]),
            postal_code: extract_header(request, POSTAL_CODE_HEADER),
            metro_code: extract_header(request, METRO_CODE_HEADER)
          )
        end

        private

        # Derive the 2-letter continent code from the country code via the countries gem.
        # Returns nil for unknown countries or continents outside the table.
        def continent_code(country_code)
          country = ISO3166::Country.new(country_code)
          CONTINENT_CODES[country&.continent]
        rescue StandardError
          nil
        end

        def extract_country_code(request)
          code = request.env[COUNTRY_HEADER]
          return nil if code.nil? || code.empty?

          code.upcase
        end

        def extract_city(request)
          city = request.env[CITY_HEADER]

          # The city header is only present when the origin request policy forwards it.
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
