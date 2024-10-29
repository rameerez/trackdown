# frozen_string_literal: true

require 'ipaddr'

module Trackdown
  class IpValidator
    class InvalidIpError < Trackdown::Error; end

    def self.validate!(ip)
      return if ip.nil?

      begin
        IPAddr.new(ip.to_s)
      rescue IPAddr::InvalidAddressError
        raise InvalidIpError, "Invalid IP address format: #{ip}"
      end
    end

    def self.private_ip?(ip)
      addr = IPAddr.new(ip.to_s)
      addr.private? || addr.loopback?
    end
  end
end
