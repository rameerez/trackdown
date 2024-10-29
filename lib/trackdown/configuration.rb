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

    def reject_private_ips?
      @reject_private_ips
    end

  end
end
