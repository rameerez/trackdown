# frozen_string_literal: true

require 'open-uri'
require 'fileutils'
require 'tempfile'
require 'zlib'
require 'rubygems/package'

module Trackdown
  # Downloads and safely installs the configured MaxMind GeoLite2 City database.
  class DatabaseUpdater
    DOWNLOAD_URL = 'https://download.maxmind.com/app/geoip_download?' \
                   'edition_id=GeoLite2-City&license_key=%<license_key>s&suffix=tar.gz'

    class << self
      def update
        download_database { |remote_file| install_download(remote_file) }

        # Serve the database we just downloaded, not the one already open in memory.
        Providers::MaxmindProvider.reset_database!

        Rails.logger.info('MaxMind database updated successfully') if defined?(Rails)
        true
      rescue OpenURI::HTTPError => e
        message = http_error_message(e)
        Rails.logger.error("Error updating MaxMind database: #{message}") if defined?(Rails)
        raise Error, message
      rescue Error
        raise
      rescue StandardError => e
        Rails.logger.error("Error updating MaxMind database: #{e.message}") if defined?(Rails)
        raise Error, "Failed to update database: #{e.message}"
      end

      private

      def download_database(&block)
        download_url = format(
          DOWNLOAD_URL,
          license_key: Trackdown.configuration.maxmind_license_key
        )
        options = {
          http_basic_authentication: [
            Trackdown.configuration.maxmind_account_id.to_s,
            Trackdown.configuration.maxmind_license_key.to_s
          ],
          ssl_verify_mode: OpenSSL::SSL::VERIFY_PEER
        }

        URI.parse(download_url).open(**options, &block)
      end

      def install_download(remote_file)
        Zlib::GzipReader.wrap(remote_file) do |gzip_reader|
          Gem::Package::TarReader.new(gzip_reader) do |tar_reader|
            entry = tar_reader.find { |candidate| database_entry?(candidate) }
            raise Error, 'The downloaded MaxMind archive did not contain a .mmdb database' unless entry

            install_database(entry)
          end
        end
      end

      def database_entry?(entry)
        entry.file? && entry.full_name.end_with?('.mmdb')
      end

      def http_error_message(error)
        case error.message
        when /401/
          'Authentication failed. Please check your MaxMind account ID and license key.'
        when /403/
          'Access forbidden. Your MaxMind license may not have access to this database.'
        else
          "HTTP Error: #{error.message}"
        end
      end

      # Write beside the destination, flush the complete database, and only then
      # replace the path. Existing MODE_FILE readers keep their already-open file
      # instead of observing a truncate-and-rewrite in progress.
      # Ruby File.rename contract:
      # https://docs.ruby-lang.org/en/3.3/File.html#method-c-rename
      # maxmind-db MODE_FILE reader:
      # https://github.com/maxmind/MaxMind-DB-Reader-ruby/blob/v1.2.0/lib/maxmind/db/file_reader.rb#L36-L55
      def install_database(entry)
        destination = Trackdown.configuration.database_path
        directory = File.dirname(destination)
        FileUtils.mkdir_p(directory)

        Tempfile.create(['trackdown-', '.mmdb'], directory) do |temporary_file|
          temporary_file.binmode
          copy_database(entry, temporary_file)
          temporary_file.flush
          temporary_file.fsync
          File.chmod(database_permissions(destination), temporary_file.path)
          temporary_file.close
          File.rename(temporary_file.path, destination)
        end
      end

      def copy_database(entry, destination)
        until entry.eof?
          chunk = entry.read(1 << 20)
          break if chunk.nil? || chunk.empty?

          destination.write(chunk)
        end
      end

      def database_permissions(destination)
        File.stat(destination).mode & 0o777
      rescue SystemCallError
        0o644
      end
    end
  end
end
