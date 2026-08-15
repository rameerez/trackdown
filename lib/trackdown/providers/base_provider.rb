# frozen_string_literal: true

require 'countries'

require_relative '../location_result'

module Trackdown
  module Providers
    class BaseProvider
      # What a CDN may legitimately send as a coordinate: a plain decimal number,
      # and nothing else. Ruling the rest out here rather than after converting
      # rejects hexadecimal ("0x10" is a perfectly good latitude of 16.0 to
      # Kernel#Float), underscored digits, and the "NaN"/"Infinity" literals.
      #
      # The digit and exponent limits are not arbitrary: no WGS-84 coordinate
      # exceeds 180, so three integer digits is already generous, and staying this
      # side of Float's range means converting a forged header can never overflow.
      # Ruby warns about an overflowing conversion in verbose mode, and untrusted
      # input must not be able to make a library talk into someone's logs.
      # https://www.rfc-editor.org/rfc/rfc5870#section-3.4.2
      DECIMAL_COORDINATE_PATTERN = /\A[+-]?\d{1,3}(?:\.\d+)?(?:[eE][+-]?\d{1,2})?\z/
      private_constant :DECIMAL_COORDINATE_PATTERN
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

      # How a result names this provider: the same symbol you'd set as
      # `config.provider`, so `result.provider_name == :cloudflare` lines up with
      # `config.provider = :cloudflare`.
      def self.provider_name
        raise NotImplementedError, "#{self} must implement .provider_name"
      end

      # Where this provider's answers physically come from, e.g.
      # :cloudflare_request_headers or :maxmind_local_database.
      def self.provider_source
        raise NotImplementedError, "#{self} must implement .provider_source"
      end

      # The provenance a request-backed provider stamps on every result.
      #
      # The trust state is :unverified unless the host's own verifier vouches for
      # the request. Trackdown never reads trust out of the headers themselves —
      # anyone who can reach an unprotected origin can send those.
      def self.request_provenance(request)
        source_was_verified = Trackdown.configuration.request_came_through_trusted_cdn_path?(
          request,
          provider_name: provider_name
        )

        {
          provider_name: provider_name,
          provider_source: provider_source,
          source_trust: source_was_verified ? :host_verified : :unverified
        }
      end

      # Helper to get emoji flag from country code
      def self.get_emoji_flag(country_code)
        return LocationResult::UNKNOWN_FLAG unless country_code.is_a?(String)
        return LocationResult::UNKNOWN_FLAG unless /\A[A-Za-z]{2}\z/.match?(country_code)

        normalized_code = country_code.upcase
        normalized_code.tr('A-Z', "\u{1F1E6}-\u{1F1FF}")
      end

      # Helper to extract country name from country code using countries gem
      def self.get_country_name(country_code)
        return LocationResult::UNKNOWN unless country_code

        country = ISO3166::Country.new(country_code)
        country&.iso_short_name || country&.name || LocationResult::UNKNOWN
      rescue StandardError
        LocationResult::UNKNOWN
      end

      # Parse an untrusted coordinate: a plain decimal within the given WGS-84
      # bounds, or nothing. The range check also settles NaN and Infinity, since
      # a Range covers neither.
      # https://www.rfc-editor.org/rfc/rfc5870#section-3.4.2
      def self.parse_coordinate(value, range:)
        return nil unless value.is_a?(String)

        decimal = value.strip
        return nil unless DECIMAL_COORDINATE_PATTERN.match?(decimal)

        coordinate = decimal.to_f
        range.cover?(coordinate) ? coordinate : nil
      end

      class << self
        protected :get_emoji_flag, :get_country_name, :parse_coordinate
      end
    end
  end
end
