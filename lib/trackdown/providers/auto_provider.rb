# frozen_string_literal: true

require_relative 'base_provider'
require_relative 'cloudflare_provider'
require_relative 'maxmind_provider'

module Trackdown
  module Providers
    # Intelligent provider that automatically selects the best available provider
    # Priority order:
    # 1. Cloudflare (fastest, zero overhead, no external dependencies)
    # 2. MaxMind (fallback when Cloudflare not available)
    #
    # This is the recommended default for most applications
    class AutoProvider < BaseProvider
      class << self
        # Auto provider is available if at least one provider is available
        def available?(request: nil)
          CloudflareProvider.available?(request: request) ||
            MaxmindProvider.available?(request: request)
        end

        # Intelligently locate IP using the best available provider
        # @param ip [String] The IP address to locate
        # @param request [ActionDispatch::Request, nil] Optional Rails request object
        # @return [LocationResult] The location information
        def locate(ip, request: nil)
          # Try Cloudflare first - it's instant and free!
          if CloudflareProvider.available?(request: request)
            return CloudflareProvider.locate(ip, request: request)
          end

          # Fall back to MaxMind if available
          if MaxmindProvider.available?(request: request)
            return MaxmindProvider.locate(ip, request: request)
          end

          # No providers available
          raise Trackdown::Error, no_provider_error_message
        end

        private

        def no_provider_error_message
          <<~MSG
            No IP geolocation provider available.

            To use Trackdown, you need at least one of:

            1. Cloudflare (recommended, zero-config):
               - Your app must be behind Cloudflare
               - Enable "IP Geolocation" in Cloudflare dashboard (Network settings)
               - Pass the request object: Trackdown.locate(ip, request: request)

            2. MaxMind database:
               - Add to Gemfile: gem 'maxmind-db'
               - Configure your MaxMind keys in config/initializers/trackdown.rb
               - Run: Trackdown.update_database

            See the Trackdown README for detailed setup instructions.
          MSG
        end
      end
    end
  end
end
