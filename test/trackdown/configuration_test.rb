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

  def test_accepts_valid_provider_cloudfront
    config = Trackdown::Configuration.new
    config.provider = :cloudfront
    assert_equal :cloudfront, config.provider
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
    assert_match(/auto, cloudflare, cloudfront, maxmind/, error.message)
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

  # === Trusted CDN path verification ===

  def test_no_verifier_by_default
    config = Trackdown::Configuration.new

    assert_nil config.trusted_cdn_path_verifier
  end

  def test_nothing_is_trusted_without_a_verifier
    config = Trackdown::Configuration.new

    refute config.request_came_through_trusted_cdn_path?(mock_request('HTTP_CF_IPCOUNTRY' => 'US'))
  end

  def test_a_block_can_vouch_for_a_request
    config = Trackdown::Configuration.new
    config.verify_request_came_through_trusted_cdn_path_with { |request| request.env['SECRET'] == 'yes' }

    assert config.request_came_through_trusted_cdn_path?(mock_request('SECRET' => 'yes'))
    refute config.request_came_through_trusted_cdn_path?(mock_request('SECRET' => 'no'))
  end

  def test_a_lambda_can_vouch_for_a_request
    config = Trackdown::Configuration.new
    config.verify_request_came_through_trusted_cdn_path_with(->(request) { request.env.key?('SECRET') })

    assert config.request_came_through_trusted_cdn_path?(mock_request('SECRET' => 'yes'))
  end

  def test_any_callable_can_vouch_for_a_request
    verifier = Object.new
    verifier.define_singleton_method(:call) { |_request| true }
    config = Trackdown::Configuration.new
    config.verify_request_came_through_trusted_cdn_path_with(verifier)

    assert config.request_came_through_trusted_cdn_path?(mock_request)
  end

  def test_the_verifier_can_be_assigned_directly
    config = Trackdown::Configuration.new
    config.trusted_cdn_path_verifier = ->(_request) { true }

    assert config.request_came_through_trusted_cdn_path?(mock_request)
  end

  def test_the_verifier_can_be_cleared
    config = Trackdown::Configuration.new
    config.verify_request_came_through_trusted_cdn_path_with { true }
    config.trusted_cdn_path_verifier = nil

    assert_nil config.trusted_cdn_path_verifier
    refute config.request_came_through_trusted_cdn_path?(mock_request)
  end

  def test_the_original_cloudflare_specific_name_still_works
    config = Trackdown::Configuration.new
    config.verify_request_came_through_trusted_cloudflare_path_with { |request| request.env['SECRET'] == 'yes' }

    assert config.request_came_through_trusted_cdn_path?(mock_request('SECRET' => 'yes'))
  end

  def test_a_verifier_that_cannot_be_called_is_rejected_immediately
    config = Trackdown::Configuration.new

    error = assert_raises(ArgumentError) do
      config.verify_request_came_through_trusted_cdn_path_with('trust me')
    end

    assert_match(/must respond to #call/, error.message)
  end

  def test_no_verifier_and_no_block_is_rejected
    config = Trackdown::Configuration.new

    assert_raises(ArgumentError) { config.verify_request_came_through_trusted_cdn_path_with }
  end

  def test_a_truthy_answer_is_enough
    config = Trackdown::Configuration.new
    config.verify_request_came_through_trusted_cdn_path_with { 'anything truthy' }

    assert_equal true, config.request_came_through_trusted_cdn_path?(mock_request)
  end

  def test_a_falsy_answer_means_unverified
    config = Trackdown::Configuration.new
    config.verify_request_came_through_trusted_cdn_path_with { nil }

    assert_equal false, config.request_came_through_trusted_cdn_path?(mock_request)
  end

  def test_nothing_is_verified_without_a_request
    config = Trackdown::Configuration.new
    config.verify_request_came_through_trusted_cdn_path_with { true }

    refute config.request_came_through_trusted_cdn_path?(nil)
  end

  def test_a_verifier_that_blows_up_means_unverified
    config = Trackdown::Configuration.new
    config.verify_request_came_through_trusted_cdn_path_with { raise 'no idea' }

    output = capture_stderr do
      refute config.request_came_through_trusted_cdn_path?(mock_request)
    end

    assert_match(/trusted CDN path verifier raised RuntimeError: no idea/, output)
    assert_match(/:unverified/, output)
  end

  def test_a_verifier_that_blows_up_complains_only_once
    config = Trackdown::Configuration.new
    config.verify_request_came_through_trusted_cdn_path_with { raise 'no idea' }

    output = capture_stderr do
      3.times { config.request_came_through_trusted_cdn_path?(mock_request) }
    end

    assert_equal 1, output.scan(/trusted CDN path verifier raised/).length
  end

  def test_a_replacement_verifier_gets_its_own_warning
    config = Trackdown::Configuration.new
    config.verify_request_came_through_trusted_cdn_path_with { raise 'first' }
    capture_stderr { config.request_came_through_trusted_cdn_path?(mock_request) }

    config.verify_request_came_through_trusted_cdn_path_with { raise 'second' }
    output = capture_stderr { config.request_came_through_trusted_cdn_path?(mock_request) }

    assert_match(/raised RuntimeError: second/, output)
  end
end
