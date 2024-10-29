require 'open-uri'
require 'zlib'
require 'rubygems/package'

module Trackdown
  class DatabaseUpdater
    DOWNLOAD_URL = "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-City&license_key=%{license_key}&suffix=tar.gz"

    class << self
      def update
        download_url = DOWNLOAD_URL % { license_key: Trackdown.configuration.maxmind_license_key }

        options = {
          http_basic_authentication: [
            Trackdown.configuration.maxmind_account_id.to_s,
            Trackdown.configuration.maxmind_license_key.to_s
          ],
          ssl_verify_mode: OpenSSL::SSL::VERIFY_PEER
        }

        URI.open(download_url, **options) do |remote_file|
          Zlib::GzipReader.wrap(remote_file) do |gz|
            Gem::Package::TarReader.new(gz) do |tar|
              tar.each do |entry|
                if entry.full_name.end_with?('.mmdb')
                  FileUtils.mkdir_p(File.dirname(Trackdown.configuration.database_path))

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
        true
      rescue OpenURI::HTTPError => e
        message = case e.message
        when /401/
          "Authentication failed. Please check your MaxMind account ID and license key."
        when /403/
          "Access forbidden. Your MaxMind license may not have access to this database."
        else
          "HTTP Error: #{e.message}"
        end
        Rails.logger.error("Error updating MaxMind database: #{message}") if defined?(Rails)
        raise Error, message
      rescue => e
        Rails.logger.error("Error updating MaxMind database: #{e.message}") if defined?(Rails)
        raise Error, "Failed to update database: #{e.message}"
      end
    end
  end
end
