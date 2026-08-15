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
    attr_reader :provider
    attr_accessor :maxmind_license_key, :maxmind_account_id, :database_path,
                  :timeout, :pool_size, :pool_timeout, :memory_mode, :reject_private_ips

    # Available provider types:
    # :auto - Use one IP-corroborated CDN provider, otherwise fall back to MaxMind (recommended)
    # :cloudflare - Only use Cloudflare headers
    # :cloudfront - Only use Amazon CloudFront headers
    # :maxmind - Only use MaxMind database
    VALID_PROVIDERS = [:auto, :cloudflare, :cloudfront, :maxmind].freeze

    def initialize
      @provider = :auto # Safe default: use one verified edge candidate, otherwise MaxMind
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
