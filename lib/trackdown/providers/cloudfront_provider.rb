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
    # request policy that forwards the CloudFront geolocation headers.
    #
    # Exact AWS viewer-location header contract (names, availability, encoding):
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html#cloudfront-headers-viewer-location
    # Exact AWS managed-policy contents:
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-origin-request-policies.html#managed-origin-request-policy-all-viewer-and-cloudfront
    #
    # IMPORTANT: Header presence does not authenticate CloudFront. A custom origin
    # must reject direct traffic before an application can trust these values. AWS's
    # exact origin-restriction guidance is:
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-overview.html
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
      # countries gem source: https://github.com/countries/countries
      CONTINENT_CODES = {
        'Africa' => 'AF',
        'Antarctica' => 'AN',
        'Asia' => 'AS',
        'Europe' => 'EU',
        'North America' => 'NA',
        'South America' => 'SA',
        'Australia' => 'OC' # the countries gem labels Oceania "Australia"
      }.freeze

      # Rack exposes ordinary HTTP request headers as HTTP_* environment entries:
      # https://github.com/rack/rack/blob/main/SPEC.rdoc#http_-headers
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

      COUNTRY_CODE_PATTERN = /\A[A-Z]{2}\z/
      INVALID_PERCENT_ESCAPE_PATTERN = /%(?![0-9A-Fa-f]{2})/
      PERCENT_ESCAPE_PATTERN = /%([0-9A-Fa-f]{2})/
      LATITUDE_RANGE = (-90.0..90.0)
      LONGITUDE_RANGE = (-180.0..180.0)

      private_constant :COUNTRY_CODE_PATTERN,
                       :INVALID_PERCENT_ESCAPE_PATTERN,
                       :PERCENT_ESCAPE_PATTERN,
                       :LATITUDE_RANGE,
                       :LONGITUDE_RANGE

      class << self
        # Check if CloudFront headers are available in the request
        def available?(request: nil)
          return false unless request

          !extract_country_code(request).nil?
        end

        # Locate IP using CloudFront headers
        # @param ip [String] The IP address (not used, as CloudFront already resolved it)
        # @param request [#env] Rack-compatible request object with CloudFront headers
        # @return [LocationResult] The location information
        def locate(_ip, request: nil)
          raise Trackdown::Error, 'CloudfrontProvider requires a request object with CloudFront headers' unless request

          country_code = extract_country_code(request)

          # If no valid country code, return unknown
          return LocationResult.new(nil, 'Unknown', 'Unknown', '🏳️') if country_code.nil?

          build_location_result(country_code, request)
        end

        def build_location_result(country_code, request)
          LocationResult.new(
            country_code,
            get_country_name(country_code),
            extract_city(request),
            get_emoji_flag(country_code),
            region: extract_header(request, REGION_HEADER),
            region_code: extract_header(request, REGION_CODE_HEADER),
            continent: continent_code(country_code),
            timezone: extract_header(request, TIMEZONE_HEADER),
            latitude: parse_coordinate(request.env[LATITUDE_HEADER], range: LATITUDE_RANGE),
            longitude: parse_coordinate(request.env[LONGITUDE_HEADER], range: LONGITUDE_RANGE),
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
          # AWS specifies an ISO 3166-1 alpha-2 value and links the authoritative list:
          # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html#cloudfront-headers-viewer-location
          code = request.env[COUNTRY_HEADER]
          return nil unless code.is_a?(String)

          normalized_code = code.upcase
          return nil unless COUNTRY_CODE_PATTERN.match?(normalized_code)

          country = ISO3166::Country.new(normalized_code)
          return nil unless country&.alpha2 == normalized_code

          normalized_code
        rescue StandardError
          nil
        end

        def extract_city(request)
          city = decode_header_value(request.env[CITY_HEADER])

          # The city header is only present when the origin request policy forwards it.
          return 'Unknown' if city.nil?

          city
        end

        def extract_header(request, header)
          decode_header_value(request.env[header])
        end

        # AWS percent-encodes non-ASCII viewer-location header characters according
        # to RFC 3986. Decode percent octets—not form data—so a literal "+" remains
        # a plus. Reject malformed escapes and invalid UTF-8 instead of exposing
        # ambiguous/binary strings to callers.
        # AWS: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html#cloudfront-headers-viewer-location
        # RFC 3986: https://www.rfc-editor.org/rfc/rfc3986#section-2.1
        def decode_header_value(value)
          return nil unless value.is_a?(String)
          return nil if value.empty?

          encoded_value = value.b
          return nil if INVALID_PERCENT_ESCAPE_PATTERN.match?(encoded_value)

          decoded_value = encoded_value.gsub(PERCENT_ESCAPE_PATTERN) do
            Regexp.last_match(1).to_i(16).chr
          end
          decoded_value.force_encoding(Encoding::UTF_8)
          return nil unless decoded_value.valid_encoding?

          decoded_value
        end

        # CloudFront defines these fields as latitude/longitude. RFC 5870 defines
        # valid WGS-84 latitude as -90..90 and longitude as -180..180, and Ruby's
        # Float#finite? rejects overflow results such as Float("1e1000") => Infinity.
        # AWS: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html#cloudfront-headers-viewer-location
        # RFC 5870: https://www.rfc-editor.org/rfc/rfc5870#section-3.4.2
        # Ruby: https://docs.ruby-lang.org/en/3.3/Float.html#method-i-finite-3F
        def parse_coordinate(value, range:)
          return nil unless value.is_a?(String)
          return nil if value.empty?

          coordinate = Float(value, exception: false)
          return nil unless coordinate&.finite? && range.cover?(coordinate)

          coordinate
        end
      end
    end
  end
end
