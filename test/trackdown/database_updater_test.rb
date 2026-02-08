# frozen_string_literal: true

require "test_helper"

class DatabaseUpdaterTest < Minitest::Test
  def setup
    super
    Trackdown.configuration.maxmind_license_key = 'test_license_key'
    Trackdown.configuration.maxmind_account_id = 'test_account_id'
    Trackdown.configuration.database_path = '/tmp/test_trackdown.mmdb'
  end

  def teardown
    File.delete(Trackdown.configuration.database_path) if File.exist?(Trackdown.configuration.database_path)
    super
  end

  def test_update_constructs_correct_url
    expected_url = "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-City&license_key=test_license_key&suffix=tar.gz"

    stub_request(:get, expected_url)
      .to_return(body: create_fake_targz, status: 200)

    Trackdown::DatabaseUpdater.update
  end

  def test_update_uses_http_basic_auth
    url = /download.maxmind.com/

    stub_request(:get, url)
      .with(basic_auth: ['test_account_id', 'test_license_key'])
      .to_return(body: create_fake_targz, status: 200)

    Trackdown::DatabaseUpdater.update
  end

  def test_update_raises_error_on_401
    url = /download.maxmind.com/

    stub_request(:get, url)
      .to_return(status: 401)

    error = assert_raises(Trackdown::Error) do
      Trackdown::DatabaseUpdater.update
    end

    assert_match(/Authentication failed/, error.message)
    assert_match(/check your MaxMind account ID and license key/, error.message)
  end

  def test_update_raises_error_on_403
    url = /download.maxmind.com/

    stub_request(:get, url)
      .to_return(status: 403)

    error = assert_raises(Trackdown::Error) do
      Trackdown::DatabaseUpdater.update
    end

    assert_match(/Access forbidden/, error.message)
    assert_match(/license may not have access/, error.message)
  end

  def test_update_returns_true_on_success
    url = /download.maxmind.com/

    stub_request(:get, url)
      .to_return(body: create_fake_targz, status: 200)

    result = Trackdown::DatabaseUpdater.update

    assert_equal true, result
  end

  def test_update_creates_directory_if_missing
    Trackdown.configuration.database_path = '/tmp/trackdown_test_nested/subdir/test.mmdb'

    url = /download.maxmind.com/

    stub_request(:get, url)
      .to_return(body: create_fake_targz, status: 200)

    Trackdown::DatabaseUpdater.update

    assert File.exist?('/tmp/trackdown_test_nested/subdir/test.mmdb')

    # Cleanup
    FileUtils.rm_rf('/tmp/trackdown_test_nested')
  end

  def test_update_writes_file_to_correct_path
    url = /download.maxmind.com/

    stub_request(:get, url)
      .to_return(body: create_fake_targz, status: 200)

    Trackdown::DatabaseUpdater.update

    assert File.exist?(Trackdown.configuration.database_path)
  end

  def test_update_raises_error_on_other_http_errors
    url = /download.maxmind.com/

    stub_request(:get, url)
      .to_return(status: 500)

    error = assert_raises(Trackdown::Error) do
      Trackdown::DatabaseUpdater.update
    end

    assert_match(/HTTP Error/, error.message)
  end

  def test_update_raises_error_on_generic_failure
    url = /download.maxmind.com/

    stub_request(:get, url)
      .to_return(body: 'not a valid gzip', status: 200)

    error = assert_raises(Trackdown::Error) do
      Trackdown::DatabaseUpdater.update
    end

    assert_match(/Failed to update database/, error.message)
  end

  private

  # Helper to create a minimal valid tar.gz file with a .mmdb file
  def create_fake_targz
    require 'stringio'
    require 'zlib'
    require 'rubygems/package'

    tar_io = StringIO.new

    Gem::Package::TarWriter.new(tar_io) do |tar|
      # Add a fake .mmdb file
      tar.add_file('GeoLite2-City_20240101/GeoLite2-City.mmdb', 0644) do |io|
        io.write('fake mmdb content')
      end
    end

    tar_io.rewind
    gz_io = StringIO.new
    gz = Zlib::GzipWriter.new(gz_io)
    gz.write(tar_io.string)
    gz.close

    gz_io.string
  end
end
