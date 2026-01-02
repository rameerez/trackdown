# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  def test_default_provider_is_auto
    config = Trackdown::Configuration.new
    assert_equal :auto, config.provider
  end

  def test_default_database_path_without_rails
    config = Trackdown::Configuration.new
    assert_equal 'db/GeoLite2-City.mmdb', config.database_path
  end

  def test_default_timeout_is_3
    config = Trackdown::Configuration.new
    assert_equal 3, config.timeout
  end

  def test_default_pool_size_is_5
    config = Trackdown::Configuration.new
    assert_equal 5, config.pool_size
  end

  def test_default_pool_timeout_is_3
    config = Trackdown::Configuration.new
    assert_equal 3, config.pool_timeout
  end

  def test_default_reject_private_ips_is_true
    config = Trackdown::Configuration.new
    assert config.reject_private_ips?
  end

  def test_accepts_valid_provider_auto
    config = Trackdown::Configuration.new
    config.provider = :auto
    assert_equal :auto, config.provider
  end

  def test_accepts_valid_provider_cloudflare
    config = Trackdown::Configuration.new
    config.provider = :cloudflare
    assert_equal :cloudflare, config.provider
  end

  def test_accepts_valid_provider_maxmind
    config = Trackdown::Configuration.new
    config.provider = :maxmind
    assert_equal :maxmind, config.provider
  end

  def test_rejects_invalid_provider
    config = Trackdown::Configuration.new

    error = assert_raises(ArgumentError) do
      config.provider = :invalid
    end

    assert_match(/Invalid provider/, error.message)
    assert_match(/auto, cloudflare, maxmind/, error.message)
  end

  def test_maxmind_license_key_can_be_set
    config = Trackdown::Configuration.new
    config.maxmind_license_key = "test_key"
    assert_equal "test_key", config.maxmind_license_key
  end

  def test_maxmind_account_id_can_be_set
    config = Trackdown::Configuration.new
    config.maxmind_account_id = "12345"
    assert_equal "12345", config.maxmind_account_id
  end

  def test_database_path_can_be_customized
    config = Trackdown::Configuration.new
    config.database_path = "/custom/path.mmdb"
    assert_equal "/custom/path.mmdb", config.database_path
  end

  def test_timeout_can_be_customized
    config = Trackdown::Configuration.new
    config.timeout = 10
    assert_equal 10, config.timeout
  end

  def test_pool_size_can_be_customized
    config = Trackdown::Configuration.new
    config.pool_size = 10
    assert_equal 10, config.pool_size
  end

  def test_reject_private_ips_can_be_disabled
    config = Trackdown::Configuration.new
    config.reject_private_ips = false
    refute config.reject_private_ips?
  end
end
