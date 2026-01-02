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
      @@warned_no_providers = false
      @@warn_mutex = Mutex.new

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

          # No providers available - fail gracefully with a warning
          warn_no_providers
          LocationResult.new(nil, 'Unknown', 'Unknown', '🏳️')
        end

        private

        def warn_no_providers
          # Only warn once per process to avoid log spam
          return if @@warned_no_providers

          @@warn_mutex.synchronize do
            return if @@warned_no_providers
            @@warned_no_providers = true

            message = "[Trackdown] No IP geolocation provider available. Returning 'Unknown' for all lookups. " \
                      "Configure Cloudflare headers or MaxMind to enable geolocation. " \
                      "See: https://github.com/rameerez/trackdown"

            if defined?(Rails)
              Rails.logger.warn(message)
            else
              warn(message)
            end
          end
        end
      end
    end
  end
end
