# frozen_string_literal: true

# Conditionally require MaxMind constants if available
begin
  require 'maxmind/db'
  MAXMIND_AVAILABLE = true
rescue LoadError
  MAXMIND_AVAILABLE = false
end

module Trackdown
  class Configuration
    attr_accessor :provider, :maxmind_license_key, :maxmind_account_id, :database_path,
                  :timeout, :pool_size, :pool_timeout, :memory_mode,
                  :reject_private_ips

    # Available provider types:
    # :auto - Try Cloudflare first, fall back to MaxMind (recommended)
    # :cloudflare - Only use Cloudflare headers
    # :maxmind - Only use MaxMind database
    VALID_PROVIDERS = [:auto, :cloudflare, :maxmind].freeze

    def initialize
      @provider = :auto # Intelligent default: try Cloudflare first, fall back to MaxMind
      @maxmind_license_key = nil
      @maxmind_account_id = nil
      @database_path = defined?(Rails) ? Rails.root.join('db', 'GeoLite2-City.mmdb').to_s : 'db/GeoLite2-City.mmdb'
      @timeout = 3 # seconds
      @pool_size = 5
      @pool_timeout = 3 # seconds
      @memory_mode = MAXMIND_AVAILABLE ? MaxMind::DB::MODE_MEMORY : nil
      @reject_private_ips = true
    end

    def provider=(value)
      unless VALID_PROVIDERS.include?(value)
        raise ArgumentError, "Invalid provider: #{value}. Must be one of: #{VALID_PROVIDERS.join(', ')}"
      end
      @provider = value
    end

    def reject_private_ips?
      @reject_private_ips
    end
  end
end
