require 'open-uri'
require 'zlib'

module Trackdown
  class DatabaseUpdater
    DOWNLOAD_URL = "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-City&license_key=%{license_key}&suffix=tar.gz"
    # DOWNLOAD_URL = "http://localhost:3002/GeoLite2-City.mmdb.tar.gz"

    class << self
      def update
        download_url = DOWNLOAD_URL % { license_key: Trackdown.configuration.maxmind_license_key }

        URI.open(download_url,
                 http_basic_authentication: [Trackdown.configuration.maxmind_account_id, Trackdown.configuration.maxmind_license_key]) do |remote_file|
          Zlib::GzipReader.wrap(remote_file) do |gz|
            File.open(Trackdown.configuration.database_path, 'wb') do |local_file|
              local_file.write(remote_file)
            end
          end
        end

        Rails.logger.info("MaxMind database updated successfully") if defined?(Rails)
      rescue => e
        Rails.logger.error("Error updating MaxMind database: #{e.message}") if defined?(Rails)
      end
    end
  end
end
