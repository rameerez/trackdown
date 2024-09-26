require 'open-uri'
require 'zlib'
require 'rubygems/package'

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
            Gem::Package::TarReader.new(gz) do |tar|
              tar.each do |entry|
                if entry.full_name.end_with?('.mmdb')
                  File.open(Trackdown.configuration.database_path, 'wb') do |file|
                    file.write(entry.read)
                  end
                  break
                end
              end
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
