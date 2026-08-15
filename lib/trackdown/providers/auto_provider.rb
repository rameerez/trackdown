# frozen_string_literal: true

require 'ipaddr'

require_relative 'base_provider'
require_relative 'cloudflare_provider'
require_relative 'cloudfront_provider'
require_relative 'maxmind_provider'

module Trackdown
  module Providers
    # Intelligent provider that automatically selects the best available provider
    # Selection order:
    # 1. Use the single edge provider whose client-IP header matches the target IP.
    # 2. Try MaxMind, then return Unknown, when no edge provider can be verified.
    # 3. Fail closed when both edge providers appear valid; header names alone cannot
    #    distinguish an authentic stacked-CDN request from forwarded viewer input.
    #
    # This is the recommended default for most applications
    #
    # IMPORTANT: When there's an upstream proxy before the CDN (e.g., a legacy
    # API gateway), the CDN's geo headers will reflect the proxy's location, not
    # the real client. AutoProvider detects this by comparing the CDN's own view
    # of the client IP (CF-Connecting-IP for Cloudflare, CloudFront-Viewer-Address
    # for CloudFront) with the passed IP and falls back to MaxMind (or Unknown when
    # MaxMind is unavailable) on a mismatch.
    #
    # Cloudflare documents that CF-Connecting-IP is added only on edge-to-origin traffic:
    # https://developers.cloudflare.com/fundamentals/reference/http-headers/#cf-connecting-ip
    # AWS documents that the managed CloudFront policy forwards every viewer header,
    # so CF-* names can still be viewer-controlled when they arrive through CloudFront:
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-origin-request-policies.html#managed-origin-request-policy-all-viewer-and-cloudfront
    class AutoProvider < BaseProvider
      CF_CONNECTING_IP_HEADER = 'HTTP_CF_CONNECTING_IP'
      CLOUDFRONT_VIEWER_ADDRESS_HEADER = 'HTTP_CLOUDFRONT_VIEWER_ADDRESS'

      @warned_no_providers = false
      @warned_ip_mismatch = false
      @warned_ambiguous_edge = false
      @warn_mutex = Mutex.new

      class << self
        # Auto provider is available if at least one provider is available
        def available?(request: nil)
          cloudflare_auto_available?(request) ||
            cloudfront_auto_available?(request) ||
            MaxmindProvider.available?(request: request)
        end

        # Intelligently locate IP using the best available provider
        # @param ip [String] The IP address to locate
        # @param request [ActionDispatch::Request, nil] Optional Rails request object
        # @return [LocationResult] The location information
        def locate(ip, request: nil)
          edge_provider = select_edge_provider(ip, request)
          return edge_provider.locate(ip, request: request) if edge_provider

          # Fall back to MaxMind if available
          return MaxmindProvider.locate(ip, request: request) if MaxmindProvider.available?(request: request)

          # No providers available - fail gracefully with a warning
          warn_no_providers
          LocationResult.new(nil, 'Unknown', 'Unknown', '🏳️')
        end

        private

        def select_edge_provider(ip, request)
          candidates = edge_candidates(ip, request)
          verified_indices = candidates.each_index.select { |index| candidates[index][:matches] }

          if verified_indices.length > 1
            # The AWS managed policy forwards all viewer headers, so a CloudFront viewer
            # can manufacture a matching CF-Connecting-IP. Conversely, Cloudflare forwards
            # ordinary viewer headers, including CloudFront-* names. With both candidates
            # matching, :auto has no authenticated signal that can safely break the tie.
            warn_ambiguous_edge(ip)
            return nil
          end

          return warn_first_unverified(candidates, ip) if verified_indices.empty?

          selected_index = verified_indices.first
          skipped_candidate = candidates.first(selected_index).find { |candidate| candidate[:available] }
          warn_unverified_candidate(skipped_candidate, ip) if skipped_candidate
          candidates[selected_index][:provider]
        end

        def edge_candidates(ip, request)
          cloudflare_available = CloudflareProvider.available?(request: request)
          cloudfront_available = CloudfrontProvider.available?(request: request)

          [
            {
              provider: CloudflareProvider,
              name: 'Cloudflare',
              header_name: 'CF-Connecting-IP',
              header_value: request&.env&.dig(CF_CONNECTING_IP_HEADER),
              available: cloudflare_available,
              matches: cloudflare_available && cloudflare_ip_matches?(ip, request)
            },
            {
              provider: CloudfrontProvider,
              name: 'CloudFront',
              header_name: 'CloudFront-Viewer-Address',
              header_value: request&.env&.dig(CLOUDFRONT_VIEWER_ADDRESS_HEADER),
              available: cloudfront_available,
              matches: cloudfront_available && cloudfront_ip_matches?(ip, request)
            }
          ]
        end

        def warn_first_unverified(candidates, ip)
          candidate = candidates.find { |item| item[:available] }
          warn_unverified_candidate(candidate, ip) if candidate
          nil
        end

        def warn_unverified_candidate(candidate, ip)
          warn_ip_mismatch(
            provider: candidate[:name],
            ip: ip,
            header_name: candidate[:header_name],
            header_value: candidate[:header_value]
          )
        end

        # Check if the IP we want to geolocate matches what Cloudflare saw as the client
        # If they don't match, there's an upstream proxy and Cloudflare's geo headers are wrong
        def cloudflare_ip_matches?(ip, request)
          return false unless request

          cf_connecting_ip = request.env[CF_CONNECTING_IP_HEADER]
          return false unless cf_connecting_ip.is_a?(String)
          return false if cf_connecting_ip.empty?

          # Normalize IPs for comparison (handle IPv6 formatting differences)
          normalized_ip = normalize_ip(ip)
          normalized_cf_ip = normalize_ip(cf_connecting_ip)
          !normalized_ip.nil? && normalized_ip == normalized_cf_ip
        end

        # Check if the IP we want to geolocate matches what CloudFront saw as the client.
        # CloudFront-Viewer-Address is "IP:port" (the port trails the last colon, which
        # also works for IPv6 since the address itself contains colons).
        def cloudfront_ip_matches?(ip, request)
          return false unless request

          normalized_ip = normalize_ip(ip)
          cloudfront_ip = cloudfront_viewer_ip(request)
          !normalized_ip.nil? && normalized_ip == cloudfront_ip
        end

        def cloudflare_auto_available?(request)
          CloudflareProvider.available?(request: request) &&
            !normalize_ip(request.env[CF_CONNECTING_IP_HEADER]).nil?
        end

        def cloudfront_auto_available?(request)
          CloudfrontProvider.available?(request: request) && !cloudfront_viewer_ip(request).nil?
        end

        # AWS specifies CloudFront-Viewer-Address as the viewer IP followed by its
        # source port. Split on the final colon for AWS's unbracketed IPv6 form, while
        # also accepting RFC 3986 bracketed IP literals defensively.
        # AWS: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html#cloudfront-headers-viewer-location
        # RFC 3986: https://www.rfc-editor.org/rfc/rfc3986#section-3.2.2
        # Port range/reserved zero: https://www.rfc-editor.org/rfc/rfc6335#section-6
        def cloudfront_viewer_ip(request)
          return nil unless request

          viewer_address = request.env[CLOUDFRONT_VIEWER_ADDRESS_HEADER]
          return nil unless viewer_address.is_a?(String)

          value = viewer_address.strip
          return nil if value.empty?

          match = value.match(/\A\[(.+)\]:(\d+)\z/)
          if match
            ip = match[1]
            port = match[2]
          else
            ip, separator, port = value.rpartition(':')
            return nil if separator.empty?
          end

          return nil unless valid_source_port?(port)

          normalize_ip(ip)
        end

        def valid_source_port?(port)
          return false unless /\A\d{1,5}\z/.match?(port)

          (1..65_535).cover?(Integer(port, 10))
        rescue ArgumentError
          false
        end

        def normalize_ip(ip)
          return nil unless ip.is_a?(String)

          value = ip.to_s.strip
          return nil if value.empty?

          parsed_ip = IPAddr.new(value)
          # IPAddr normalizes equivalent IPv6 spellings; #native converts an
          # IPv4-mapped IPv6 address to its native IPv4 representation.
          # https://docs.ruby-lang.org/en/3.3/IPAddr.html
          # https://docs.ruby-lang.org/en/3.3/IPAddr.html#method-i-native
          parsed_ip = parsed_ip.native if parsed_ip.ipv4_mapped?
          parsed_ip.to_s.downcase
        rescue IPAddr::Error
          nil
        end

        def warn_ip_mismatch(provider:, ip:, header_name:, header_value:)
          return if @warned_ip_mismatch

          warn_mutex.synchronize do
            return if @warned_ip_mismatch

            @warned_ip_mismatch = true

            reason = if header_value.nil? || (header_value.is_a?(String) && header_value.empty?)
                       "#{header_name} is missing"
                     elsif !header_value.is_a?(String)
                       "#{header_name} is malformed"
                     else
                       "#{header_name} (#{header_value}) does not match the request IP (#{ip})"
                     end
            message = "[Trackdown] Cannot verify #{provider} geolocation because #{reason}. " \
                      "Skipping #{provider} and trying the next available provider."

            if defined?(Rails)
              Rails.logger.info(message)
            else
              warn(message)
            end
          end
        end

        def warn_ambiguous_edge(ip)
          return if @warned_ambiguous_edge

          warn_mutex.synchronize do
            return if @warned_ambiguous_edge

            @warned_ambiguous_edge = true

            message = "[Trackdown] Both Cloudflare and CloudFront headers match request IP (#{ip}). " \
                      'Because forwarded viewer headers can spoof this combination, :auto cannot ' \
                      'choose safely. Trying MaxMind and otherwise returning Unknown; configure ' \
                      'an explicit provider if this is an intentional stacked-CDN deployment.'

            if defined?(Rails)
              Rails.logger.warn(message)
            else
              warn(message)
            end
          end
        end

        def warn_no_providers
          # Only warn once per process to avoid log spam
          return if @warned_no_providers

          warn_mutex.synchronize do
            return if @warned_no_providers

            @warned_no_providers = true

            message = "[Trackdown] No IP geolocation provider available. Returning 'Unknown' for all lookups. " \
                      'Configure verified Cloudflare or CloudFront headers, or MaxMind, to enable geolocation. ' \
                      'See: https://github.com/rameerez/trackdown'

            if defined?(Rails)
              Rails.logger.warn(message)
            else
              warn(message)
            end
          end
        end

        def warn_mutex
          @warn_mutex ||= Mutex.new
        end
      end
    end
  end
end
