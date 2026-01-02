# frozen_string_literal: true

require "test_helper"

class CloudflareProviderTest < Minitest::Test
  def test_available_returns_false_without_request
    refute Trackdown::Providers::CloudflareProvider.available?
  end

  def test_available_returns_false_with_nil_request
    refute Trackdown::Providers::CloudflareProvider.available?(request: nil)
  end

  def test_available_returns_false_without_country_header
    request = mock_request_without_cloudflare
    refute Trackdown::Providers::CloudflareProvider.available?(request: request)
  end

  def test_available_returns_false_with_empty_country_header
    request = Object.new
    request.define_singleton_method(:env) { {'HTTP_CF_IPCOUNTRY' => ''} }
    refute Trackdown::Providers::CloudflareProvider.available?(request: request)
  end

  def test_available_returns_false_with_xx_code
    request = mock_request_with_xx_country
    refute Trackdown::Providers::CloudflareProvider.available?(request: request)
  end

  def test_available_returns_true_with_valid_header
    request = mock_cloudflare_request
    assert Trackdown::Providers::CloudflareProvider.available?(request: request)
  end

  def test_available_returns_true_with_t1_tor_code
    request = mock_request_with_tor
    assert Trackdown::Providers::CloudflareProvider.available?(request: request)
  end

  def test_locate_requires_request_object
    error = assert_raises(Trackdown::Error) do
      Trackdown::Providers::CloudflareProvider.locate('8.8.8.8')
    end

    assert_match(/requires a request object/, error.message)
  end

  def test_locate_extracts_country_from_header
    request = mock_cloudflare_request(country: 'GB', city: 'London')
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_equal 'GB', result.country_code
    assert_equal 'United Kingdom of Great Britain and Northern Ireland', result.country_name
  end

  def test_locate_extracts_city_from_header
    request = mock_cloudflare_request(country: 'US', city: 'New York')
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_equal 'New York', result.city
  end

  def test_locate_returns_unknown_for_missing_city
    request = mock_cloudflare_request(country: 'US', city: nil)
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_equal 'Unknown', result.city
  end

  def test_locate_returns_unknown_for_empty_city
    request = mock_cloudflare_request(country: 'US', city: '')
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_equal 'Unknown', result.city
  end

  def test_locate_returns_unknown_for_xx_country_code
    request = mock_request_with_xx_country
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_nil result.country_code
    assert_equal 'Unknown', result.country_name
    assert_equal 'Unknown', result.city
    assert_equal '🏳️', result.flag_emoji
  end

  def test_locate_handles_t1_tor_code
    request = mock_request_with_tor
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_equal 'T1', result.country_code
    # T1 is not a real country code, so it should return Unknown
    assert_equal 'Unknown', result.country_name
  end

  def test_locate_returns_location_result
    request = mock_cloudflare_request
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_instance_of Trackdown::LocationResult, result
  end

  def test_locate_upcases_lowercase_country_code
    request = Object.new
    request.define_singleton_method(:env) { {'HTTP_CF_IPCOUNTRY' => 'us'} }
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_equal 'US', result.country_code
  end

  def test_locate_with_multiple_countries
    # Test a variety of country codes
    [
      ['FR', 'Paris', '🇫🇷'],
      ['DE', 'Berlin', '🇩🇪'],
      ['JP', 'Tokyo', '🇯🇵'],
      ['BR', 'São Paulo', '🇧🇷']
    ].each do |country_code, city, expected_flag|
      request = mock_cloudflare_request(country: country_code, city: city)
      result = Trackdown::Providers::CloudflareProvider.locate('1.2.3.4', request: request)

      assert_equal country_code, result.country_code
      assert_equal city, result.city
      assert_equal expected_flag, result.flag_emoji
    end
  end
end
