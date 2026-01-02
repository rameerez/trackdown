# frozen_string_literal: true

require_relative 'location_result'
require_relative 'ip_validator'
require_relative 'providers/auto_provider'
require_relative 'providers/cloudflare_provider'
require_relative 'providers/maxmind_provider'

module Trackdown
  class IpLocator
    class << self
      # Locate an IP address using the configured provider
      # @param ip [String] The IP address to locate
      # @param request [ActionDispatch::Request, nil] Optional Rails request object for Cloudflare provider
      # @return [LocationResult] The location information
      def locate(ip, request: nil)
        IpValidator.validate!(ip)

        if Trackdown.configuration.reject_private_ips? && IpValidator.private_ip?(ip)
          raise IpValidator::InvalidIpError, "Private IP addresses are not allowed"
        end

        provider = get_provider
        provider.locate(ip, request: request)
      end

      private

      def get_provider
        case Trackdown.configuration.provider
        when :auto
          Providers::AutoProvider
        when :cloudflare
          Providers::CloudflareProvider
        when :maxmind
          Providers::MaxmindProvider
        else
          raise Trackdown::Error, "Unknown provider: #{Trackdown.configuration.provider}"
        end
      end
    end
  end
end
