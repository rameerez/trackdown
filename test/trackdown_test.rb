# frozen_string_literal: true

require "test_helper"

class TrackdownTest < Minitest::Test
  def test_has_version_number
    refute_nil Trackdown::VERSION
  end

  def test_configure_yields_configuration
    Trackdown.configure do |config|
      assert_instance_of Trackdown::Configuration, config
    end
  end

  def test_configure_updates_configuration
    Trackdown.configure do |config|
      config.provider = :cloudflare
      config.timeout = 10
    end

    assert_equal :cloudflare, Trackdown.configuration.provider
    assert_equal 10, Trackdown.configuration.timeout
  end

  def test_locate_delegates_to_ip_locator
    expected_result = Trackdown::LocationResult.new('US', 'United States', 'Seattle', '🇺🇸')

    Trackdown::IpLocator.expects(:locate).with('8.8.8.8', request: nil).returns(expected_result)

    result = Trackdown.locate('8.8.8.8')

    assert_equal 'US', result.country_code
  end

  def test_locate_passes_request_parameter
    request = mock_cloudflare_request
    expected_result = Trackdown::LocationResult.new('GB', 'United Kingdom', 'London', '🇬🇧')

    Trackdown::IpLocator.expects(:locate).with('1.2.3.4', request: request).returns(expected_result)

    result = Trackdown.locate('1.2.3.4', request: request)

    assert_equal 'GB', result.country_code
  end

  def test_update_database_delegates_to_database_updater
    Trackdown::DatabaseUpdater.expects(:update).returns(true)

    result = Trackdown.update_database

    assert_equal true, result
  end

  def test_database_exists_checks_file_existence
    Trackdown.configuration.database_path = '/nonexistent/file.mmdb'

    refute Trackdown.database_exists?
  end

  def test_database_exists_returns_true_when_file_present
    Trackdown.configuration.database_path = '/tmp/test.mmdb'

    File.stub :exist?, true do
      assert Trackdown.database_exists?
    end
  end

  def test_ensure_database_exists_raises_when_missing
    Trackdown.configuration.database_path = '/nonexistent/file.mmdb'

    error = assert_raises(Trackdown::Error) do
      Trackdown.ensure_database_exists!
    end

    assert_match(/MaxMind database not found/, error.message)
    assert_match(/Trackdown.update_database/, error.message)
  end

  def test_ensure_database_exists_passes_when_present
    Trackdown.configuration.database_path = '/tmp/test.mmdb'

    File.stub :exist?, true do
      # Should not raise
      assert_nil Trackdown.ensure_database_exists!
    end
  end

  def test_configuration_returns_same_instance
    config1 = Trackdown.configuration
    config2 = Trackdown.configuration

    assert_same config1, config2
  end

  def test_configuration_persists_across_calls
    Trackdown.configuration.provider = :maxmind

    assert_equal :maxmind, Trackdown.configuration.provider
  end
end
