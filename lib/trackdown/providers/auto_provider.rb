# frozen_string_literal: true

require 'ipaddr'

require_relative 'base_provider'
require_relative 'cloudflare_provider'
require_relative 'cloudfront_provider'
require_relative 'maxmind_provider'

module Trackdown
  module Providers
    # Intelligent provider that automatically selects the best available provider
    # Priority order:
    # 1. Cloudflare (fastest, zero overhead, no external dependencies)
    # 2. CloudFront (same — edge headers when behind the AWS CDN)
    # 3. MaxMind (fallback when no edge headers available or IP mismatch)
    #
    # This is the recommended default for most applications
    #
    # IMPORTANT: When there's an upstream proxy before the CDN (e.g., a legacy
    # API gateway), the CDN's geo headers will reflect the proxy's location, not
    # the real client. AutoProvider detects this by comparing the CDN's own view
    # of the client IP (CF-Connecting-IP for Cloudflare, CloudFront-Viewer-Address
    # for CloudFront) with the passed IP and falls back to MaxMind on a mismatch.
    class AutoProvider < BaseProvider
      CF_CONNECTING_IP_HEADER = 'HTTP_CF_CONNECTING_IP'
      CLOUDFRONT_VIEWER_ADDRESS_HEADER = 'HTTP_CLOUDFRONT_VIEWER_ADDRESS'

      @@warned_no_providers = false
      @@warned_ip_mismatch = false
      @@warn_mutex = Mutex.new

      class << self
        # Auto provider is available if at least one provider is available
        def available?(request: nil)
          CloudflareProvider.available?(request: request) ||
            CloudfrontProvider.available?(request: request) ||
            MaxmindProvider.available?(request: request)
        end

        # Intelligently locate IP using the best available provider
        # @param ip [String] The IP address to locate
        # @param request [ActionDispatch::Request, nil] Optional Rails request object
        # @return [LocationResult] The location information
        def locate(ip, request: nil)
          # Try Cloudflare first - it's instant and free!
          # But only if the IP matches what Cloudflare geolocated
          if CloudflareProvider.available?(request: request)
            if cloudflare_ip_matches?(ip, request)
              return CloudflareProvider.locate(ip, request: request)
            else
              # IP mismatch: there's likely an upstream proxy before Cloudflare
              # Cloudflare's geo headers are based on the proxy IP, not the real client
              # Fall back to MaxMind with the correct IP
              warn_ip_mismatch(ip, request)
            end
          end

          # Then try CloudFront edge headers, with the same IP-match guard
          if CloudfrontProvider.available?(request: request)
            if cloudfront_ip_matches?(ip, request)
              return CloudfrontProvider.locate(ip, request: request)
            else
              warn_ip_mismatch(ip, request)
            end
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

        # Check if the IP we want to geolocate matches what Cloudflare saw as the client
        # If they don't match, there's an upstream proxy and Cloudflare's geo headers are wrong
        def cloudflare_ip_matches?(ip, request)
          return true unless request # No request means we can't check

          cf_connecting_ip = request.env[CF_CONNECTING_IP_HEADER]
          return true if cf_connecting_ip.nil? || cf_connecting_ip.empty?

          # Normalize IPs for comparison (handle IPv6 formatting differences)
          normalize_ip(ip) == normalize_ip(cf_connecting_ip)
        end

        # Check if the IP we want to geolocate matches what CloudFront saw as the client.
        # CloudFront-Viewer-Address is "IP:port" (the port trails the last colon, which
        # also works for IPv6 since the address itself contains colons).
        def cloudfront_ip_matches?(ip, request)
          return true unless request

          viewer_address = request.env[CLOUDFRONT_VIEWER_ADDRESS_HEADER]
          return true if viewer_address.nil? || viewer_address.empty?

          cloudfront_ip = viewer_address.rpartition(':').first
          cloudfront_ip = viewer_address if cloudfront_ip.empty? # no port present

          normalize_ip(ip) == normalize_ip(cloudfront_ip)
        end

        def normalize_ip(ip)
          return nil if ip.nil?

          value = ip.to_s.strip
          return nil if value.empty?

          parsed_ip = IPAddr.new(value)
          parsed_ip = parsed_ip.native if parsed_ip.ipv4_mapped?
          parsed_ip.to_s.downcase
        rescue IPAddr::InvalidAddressError
          # If parsing fails, fall back to string comparison so we still have
          # deterministic behavior and can trigger MaxMind fallback on mismatch.
          value.downcase
        end

        def warn_ip_mismatch(ip, request)
          return if @@warned_ip_mismatch

          @@warn_mutex.synchronize do
            return if @@warned_ip_mismatch
            @@warned_ip_mismatch = true

            cdn_header, cdn_ip =
              if request&.env&.key?(CF_CONNECTING_IP_HEADER)
                ['CF-Connecting-IP', request.env[CF_CONNECTING_IP_HEADER]]
              else
                ['CloudFront-Viewer-Address', request&.env&.dig(CLOUDFRONT_VIEWER_ADDRESS_HEADER)]
              end
            message = "[Trackdown] IP mismatch detected: request IP (#{ip}) differs from " \
                      "#{cdn_header} (#{cdn_ip}). This usually means there's an upstream " \
                      "proxy before the CDN. Falling back to MaxMind for accurate geolocation."

            if defined?(Rails)
              Rails.logger.info(message)
            else
              warn(message)
            end
          end
        end

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
