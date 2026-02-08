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

  # === New header extraction tests ===

  def test_locate_extracts_region_header
    request = mock_cloudflare_request(country: 'US', city: 'San Francisco', region: 'California')
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_equal 'California', result.region
  end

  def test_locate_extracts_region_code_header
    request = mock_cloudflare_request(country: 'US', city: 'San Francisco', region_code: 'CA')
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_equal 'CA', result.region_code
  end

  def test_locate_extracts_latitude_header
    request = mock_cloudflare_request(country: 'US', city: 'San Francisco', latitude: '37.7749')
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_in_delta 37.7749, result.latitude
  end

  def test_locate_extracts_longitude_header
    request = mock_cloudflare_request(country: 'US', city: 'San Francisco', longitude: '-122.4194')
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_in_delta(-122.4194, result.longitude)
  end

  def test_locate_extracts_timezone_header
    request = mock_cloudflare_request(country: 'US', city: 'San Francisco', timezone: 'America/Los_Angeles')
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_equal 'America/Los_Angeles', result.timezone
  end

  def test_locate_extracts_continent_header
    request = mock_cloudflare_request(country: 'US', city: 'San Francisco', continent: 'NA')
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_equal 'NA', result.continent
  end

  def test_locate_with_all_new_headers_present
    request = mock_cloudflare_request_with_all_headers
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_equal 'US', result.country_code
    assert_equal 'San Francisco', result.city
    assert_equal 'California', result.region
    assert_equal 'CA', result.region_code
    assert_equal 'NA', result.continent
    assert_equal 'America/Los_Angeles', result.timezone
    assert_in_delta 37.7749, result.latitude
    assert_in_delta(-122.4194, result.longitude)
    assert_equal '94107', result.postal_code
    assert_equal '807', result.metro_code
  end

  def test_locate_missing_region_header_returns_nil
    request = mock_cloudflare_request(country: 'US', city: 'San Francisco')
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_nil result.region
  end

  def test_locate_missing_region_code_header_returns_nil
    request = mock_cloudflare_request(country: 'US', city: 'San Francisco')
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_nil result.region_code
  end

  def test_locate_missing_latitude_header_returns_nil
    request = mock_cloudflare_request(country: 'US', city: 'San Francisco')
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_nil result.latitude
  end

  def test_locate_missing_longitude_header_returns_nil
    request = mock_cloudflare_request(country: 'US', city: 'San Francisco')
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_nil result.longitude
  end

  def test_locate_missing_timezone_header_returns_nil
    request = mock_cloudflare_request(country: 'US', city: 'San Francisco')
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_nil result.timezone
  end

  def test_locate_missing_continent_header_returns_nil
    request = mock_cloudflare_request(country: 'US', city: 'San Francisco')
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_nil result.continent
  end

  def test_locate_extracts_postal_code_header
    request = mock_cloudflare_request(country: 'US', city: 'San Francisco', postal_code: '94107')
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_equal '94107', result.postal_code
  end

  def test_locate_extracts_metro_code_header
    request = mock_cloudflare_request(country: 'US', city: 'San Francisco', metro_code: '807')
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_equal '807', result.metro_code
  end

  def test_locate_missing_postal_code_header_returns_nil
    request = mock_cloudflare_request(country: 'US', city: 'San Francisco')
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_nil result.postal_code
  end

  def test_locate_missing_metro_code_header_returns_nil
    request = mock_cloudflare_request(country: 'US', city: 'San Francisco')
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_nil result.metro_code
  end

  # === Latitude/longitude parsing edge cases ===

  def test_parse_coordinate_with_valid_positive_float
    request = mock_cloudflare_request(country: 'US', city: 'SF', latitude: '37.7749')
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_in_delta 37.7749, result.latitude
  end

  def test_parse_coordinate_with_valid_negative_float
    request = mock_cloudflare_request(country: 'US', city: 'SF', longitude: '-122.5773')
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_in_delta(-122.5773, result.longitude)
  end

  def test_parse_coordinate_with_zero
    request = mock_cloudflare_request(country: 'GH', city: 'Accra', latitude: '0', longitude: '0')
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_in_delta 0.0, result.latitude
    assert_in_delta 0.0, result.longitude
  end

  def test_parse_coordinate_with_empty_string_returns_nil
    request = Object.new
    env = {
      'HTTP_CF_IPCOUNTRY' => 'US',
      'HTTP_CF_IPCITY' => 'SF',
      'HTTP_CF_IPLATITUDE' => '',
      'HTTP_CF_IPLONGITUDE' => ''
    }
    request.define_singleton_method(:env) { env }
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_nil result.latitude
    assert_nil result.longitude
  end

  def test_parse_coordinate_with_non_numeric_string_returns_nil
    request = Object.new
    env = {
      'HTTP_CF_IPCOUNTRY' => 'US',
      'HTTP_CF_IPCITY' => 'SF',
      'HTTP_CF_IPLATITUDE' => 'abc',
      'HTTP_CF_IPLONGITUDE' => 'xyz'
    }
    request.define_singleton_method(:env) { env }
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_nil result.latitude
    assert_nil result.longitude
  end

  def test_parse_coordinate_with_nil_returns_nil
    request = Object.new
    env = {
      'HTTP_CF_IPCOUNTRY' => 'US',
      'HTTP_CF_IPCITY' => 'SF'
      # HTTP_CF_IPLATITUDE and HTTP_CF_IPLONGITUDE not present (nil)
    }
    request.define_singleton_method(:env) { env }
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_nil result.latitude
    assert_nil result.longitude
  end

  # === extract_header edge cases ===

  def test_extract_header_present_returns_value
    request = mock_cloudflare_request(country: 'US', city: 'SF', region: 'California')
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_equal 'California', result.region
  end

  def test_extract_header_absent_returns_nil
    request = mock_cloudflare_request(country: 'US', city: 'SF')
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_nil result.region
  end

  def test_extract_header_empty_string_returns_nil
    request = Object.new
    env = {
      'HTTP_CF_IPCOUNTRY' => 'US',
      'HTTP_CF_IPCITY' => 'SF',
      'HTTP_CF_REGION' => ''
    }
    request.define_singleton_method(:env) { env }
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_nil result.region
  end

  def test_xx_country_code_does_not_populate_new_fields
    request = mock_request_with_xx_country
    result = Trackdown::Providers::CloudflareProvider.locate('8.8.8.8', request: request)

    assert_nil result.region
    assert_nil result.region_code
    assert_nil result.continent
    assert_nil result.timezone
    assert_nil result.latitude
    assert_nil result.longitude
    assert_nil result.postal_code
    assert_nil result.metro_code
  end
end
