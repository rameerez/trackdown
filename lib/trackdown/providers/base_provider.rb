# frozen_string_literal: true

require 'countries'

require_relative '../location_result'

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
        {
          provider_name: provider_name,
          provider_source: provider_source,
          source_trust: Trackdown.configuration.request_came_through_trusted_cdn_path?(request) ? :host_verified : :unverified
        }
      end

      protected

      # Helper to get emoji flag from country code
      def self.get_emoji_flag(country_code)
        country_code ? country_code.tr('A-Z', "\u{1F1E6}-\u{1F1FF}") : LocationResult::UNKNOWN_FLAG
      end

      # Helper to extract country name from country code using countries gem
      def self.get_country_name(country_code)
        return LocationResult::UNKNOWN unless country_code

        country = ISO3166::Country.new(country_code)
        country&.iso_short_name || country&.name || LocationResult::UNKNOWN
      rescue StandardError
        LocationResult::UNKNOWN
      end
    end
  end
end
