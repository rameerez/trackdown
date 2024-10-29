# frozen_string_literal: true

module Trackdown
  class Configuration
    attr_accessor :maxmind_license_key, :maxmind_account_id, :database_path,
                  :timeout, :pool_size, :pool_timeout, :memory_mode,
                  :reject_private_ips

    def initialize
      @maxmind_license_key = nil
      @maxmind_account_id = nil
      @database_path = defined?(Rails) ? Rails.root.join('db', 'GeoLite2-City.mmdb').to_s : 'db/GeoLite2-City.mmdb'
      @timeout = 3 # seconds
      @pool_size = 5
      @pool_timeout = 3 # seconds
      @memory_mode = MaxMind::DB::MODE_MEMORY
      @reject_private_ips = true
    end

    def validate!
      missing = []
      missing << 'maxmind_license_key' if maxmind_license_key.nil?
      missing << 'maxmind_account_id' if maxmind_account_id.nil?

      raise Error, "Missing required configuration: #{missing.join(', ')} – Please set these in your config/initializers/trackdown.rb initializer." unless missing.empty?

      validate_paths!
      validate_timeouts!
    end

    def reject_private_ips?
      @reject_private_ips
    end

    private

    def validate_paths!
      unless database_path && !database_path.empty?
        raise Error, "database_path cannot be empty"
      end
    end

    def validate_timeouts!
      raise Error, "timeout must be positive" unless timeout.positive?
      raise Error, "pool_timeout must be positive" unless pool_timeout.positive?
      raise Error, "pool_size must be positive" unless pool_size.positive?
    end
  end
end
