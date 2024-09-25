module Trackdown
  class Configuration
    attr_accessor :maxmind_license_key, :maxmind_account_id, :database_path

    def initialize
      @maxmind_license_key = nil
      @maxmind_account_id = nil
      @database_path = Rails.root.join('db', 'GeoLite2-City.mmdb').to_s if defined?(Rails)
    end
  end
end
