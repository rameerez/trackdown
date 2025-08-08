# frozen_string_literal: true

require 'test_helper'
require 'stringio'

class DatabaseUpdaterTest < Minitest::Test
  def setup
    Trackdown.instance_variable_set(:@configuration, nil)
    @tmp_dir = File.join(Dir.pwd, 'tmp', 'db_updater')
    FileUtils.mkdir_p(@tmp_dir)
    Trackdown.configuration.database_path = File.join(@tmp_dir, 'GeoLite2-City.mmdb')
    Trackdown.configuration.maxmind_license_key = 'key'
    Trackdown.configuration.maxmind_account_id = 'acct'

    # Ensure Rails stubs exist for logging and path resolution
    Object.const_set(:Rails, Module.new) unless defined?(::Rails)
    ::Rails.define_singleton_method(:root) { Pathname.new(Dir.pwd) } unless ::Rails.respond_to?(:root)
    unless ::Rails.respond_to?(:logger)
      ::Rails.define_singleton_method(:logger) do
        @__td_logger__ ||= Object.new.tap do |o|
          def o.info(*); end
          def o.error(*); end
        end
      end
    end
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  def fake_tar_gz_with_mmdb(content = 'MMDB_DATA')
    # Create a tar with one .mmdb file, then gzip it, return StringIO
    tar_io = StringIO.new
    Gem::Package::TarWriter.new(tar_io) do |tar|
      tar.add_file('GeoLite2-City_2024/GeoLite2-City.mmdb', 0644) do |tf|
        tf.write(content)
      end
    end
    tar_io.rewind
    tar_string = tar_io.string

    gz_io = StringIO.new
    Zlib::GzipWriter.wrap(gz_io) { |gz| gz.write(tar_string) }
    gz_io.rewind
    StringIO.new(gz_io.string)
  end

  def test_update_downloads_and_writes_mmdb
    remote = fake_tar_gz_with_mmdb('abc123')
    URI.stubs(:open).yields(remote).returns(remote)

    assert_equal true, Trackdown::DatabaseUpdater.update
    assert_equal true, File.exist?(Trackdown.configuration.database_path)
    assert_equal 'abc123', File.binread(Trackdown.configuration.database_path)
  end

  def test_update_http_401_error
    URI.stubs(:open).raises(OpenURI::HTTPError.new('401 Unauthorized', StringIO.new))
    error = assert_raises(Trackdown::Error) { Trackdown::DatabaseUpdater.update }
    assert_match(/Authentication failed/i, error.message)
  end

  def test_update_http_403_error
    URI.stubs(:open).raises(OpenURI::HTTPError.new('403 Forbidden', StringIO.new))
    error = assert_raises(Trackdown::Error) { Trackdown::DatabaseUpdater.update }
    assert_match(/Access forbidden/i, error.message)
  end

  def test_update_other_http_error
    URI.stubs(:open).raises(OpenURI::HTTPError.new('500 Internal Server Error', StringIO.new))
    error = assert_raises(Trackdown::Error) { Trackdown::DatabaseUpdater.update }
    assert_match(/HTTP Error: 500 Internal Server Error/, error.message)
  end

  def test_update_generic_error
    URI.stubs(:open).raises(StandardError.new('boom'))
    error = assert_raises(Trackdown::Error) { Trackdown::DatabaseUpdater.update }
    assert_match(/Failed to update database: boom/, error.message)
  end
end