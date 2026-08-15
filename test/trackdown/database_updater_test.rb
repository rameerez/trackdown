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
    assert_equal 'fake mmdb content', File.binread(Trackdown.configuration.database_path)
  end

  def test_update_replaces_the_path_without_truncating_an_open_reader
    # MODE_FILE readers retain an open file just like this handle:
    # https://github.com/maxmind/MaxMind-DB-Reader-ruby/blob/v1.2.0/lib/maxmind/db/file_reader.rb#L36-L55
    # Trackdown installs with one same-directory rename:
    # https://docs.ruby-lang.org/en/3.3/File.html#method-c-rename
    File.binwrite(Trackdown.configuration.database_path, 'working database')
    open_reader = File.open(Trackdown.configuration.database_path, 'rb')
    stub_request(:get, /download.maxmind.com/)
      .to_return(body: create_fake_targz, status: 200)

    Trackdown::DatabaseUpdater.update

    assert_equal 'fake mmdb content', File.binread(Trackdown.configuration.database_path)
    assert_equal 'working database', open_reader.read
  ensure
    open_reader&.close
  end

  def test_update_keeps_the_working_database_when_the_archive_has_no_database
    File.binwrite(Trackdown.configuration.database_path, 'working database')
    url = /download.maxmind.com/

    stub_request(:get, url)
      .to_return(body: create_fake_targz(include_database: false), status: 200)

    error = assert_raises(Trackdown::Error) do
      Trackdown::DatabaseUpdater.update
    end

    assert_match(/did not contain a .mmdb database/, error.message)
    assert_equal 'working database', File.binread(Trackdown.configuration.database_path)
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
  def create_fake_targz(include_database: true)
    require 'stringio'
    require 'zlib'
    require 'rubygems/package'

    tar_io = StringIO.new

    Gem::Package::TarWriter.new(tar_io) do |tar|
      if include_database
        # Add a fake .mmdb file
        tar.add_file('GeoLite2-City_20240101/GeoLite2-City.mmdb', 0644) do |io|
          io.write('fake mmdb content')
        end
      else
        tar.add_file('GeoLite2-City_20240101/COPYRIGHT.txt', 0644) do |io|
          io.write('not a database')
        end
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
