# frozen_string_literal: true

require 'test_helper'

class TrackdownTest < Minitest::Test
  def setup
    # reset configuration for isolation
    Trackdown.instance_variable_set(:@configuration, nil)
  end

  def test_configuration_defaults
    config = Trackdown.configuration
    assert_nil config.maxmind_license_key
    assert_nil config.maxmind_account_id
    assert_kind_of String, config.database_path
    assert_equal 3, config.timeout
    assert_equal 5, config.pool_size
    assert_equal 3, config.pool_timeout
    assert_equal MaxMind::DB::MODE_MEMORY, config.memory_mode
    assert_equal true, config.reject_private_ips?
  end

  def test_configure_sets_values
    Trackdown.configure do |c|
      c.maxmind_license_key = 'abc'
      c.maxmind_account_id = 'id'
      c.database_path = '/tmp/test.mmdb'
      c.timeout = 7
      c.pool_size = 9
      c.pool_timeout = 11
      c.memory_mode = MaxMind::DB::MODE_FILE
      c.reject_private_ips = false
    end

    c = Trackdown.configuration
    assert_equal 'abc', c.maxmind_license_key
    assert_equal 'id', c.maxmind_account_id
    assert_equal '/tmp/test.mmdb', c.database_path
    assert_equal 7, c.timeout
    assert_equal 9, c.pool_size
    assert_equal 11, c.pool_timeout
    assert_equal MaxMind::DB::MODE_FILE, c.memory_mode
    assert_equal false, c.reject_private_ips?
  end

  def test_database_exists_predicate
    Trackdown.configuration.database_path = '/tmp/nonexistent.mmdb'
    File.stubs(:exist?).with('/tmp/nonexistent.mmdb').returns(true)
    assert_equal true, Trackdown.database_exists?
  end

  def test_ensure_database_exists_raises_when_missing
    Trackdown.configuration.database_path = '/tmp/missing.mmdb'
    File.stubs(:exist?).with('/tmp/missing.mmdb').returns(false)
    error = assert_raises(Trackdown::Error) { Trackdown.ensure_database_exists! }
    assert_match(/MaxMind database not found/i, error.message)
  end

  def test_locate_delegates_to_ip_locator_after_ensuring_db
    Trackdown.configuration.database_path = '/tmp/existent.mmdb'
    File.stubs(:exist?).with('/tmp/existent.mmdb').returns(true)

    mock_result = Trackdown::LocationResult.new('US', 'United States', 'Mountain View', '🇺🇸')
    Trackdown::IpLocator.expects(:locate).with('8.8.8.8').returns(mock_result)

    result = Trackdown.locate('8.8.8.8')
    assert_equal 'US', result.country_code
  end

  def test_update_database_delegates_to_updater
    Trackdown::DatabaseUpdater.expects(:update).returns(true)
    assert_equal true, Trackdown.update_database
  end
end