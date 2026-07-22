# frozen_string_literal: true

require "test_helper"

class CloudfrontProviderTest < Minitest::Test
  def test_available_returns_false_without_request
    refute Trackdown::Providers::CloudfrontProvider.available?
  end

  def test_available_returns_false_with_nil_request
    refute Trackdown::Providers::CloudfrontProvider.available?(request: nil)
  end

  def test_available_returns_false_without_country_header
    request = mock_request_without_cloudflare
    refute Trackdown::Providers::CloudfrontProvider.available?(request: request)
  end

  def test_available_returns_false_with_empty_country_header
    request = mock_cloudfront_request(country: '')
    refute Trackdown::Providers::CloudfrontProvider.available?(request: request)
  end

  def test_available_returns_true_with_valid_header
    request = mock_cloudfront_request
    assert Trackdown::Providers::CloudfrontProvider.available?(request: request)
  end

  def test_locate_requires_request_object
    error = assert_raises(Trackdown::Error) do
      Trackdown::Providers::CloudfrontProvider.locate('8.8.8.8')
    end

    assert_match(/requires a request object/, error.message)
  end

  def test_locate_extracts_country_from_header
    request = mock_cloudfront_request(country: 'GB', city: 'London')
    result = Trackdown::Providers::CloudfrontProvider.locate('8.8.8.8', request: request)

    assert_equal 'GB', result.country_code
    assert_equal 'United Kingdom of Great Britain and Northern Ireland', result.country_name
  end

  def test_locate_extracts_city_from_header
    request = mock_cloudfront_request(country: 'US', city: 'New York')
    result = Trackdown::Providers::CloudfrontProvider.locate('8.8.8.8', request: request)

    assert_equal 'New York', result.city
  end

  def test_locate_returns_unknown_for_missing_city
    request = mock_cloudfront_request(country: 'US', city: nil)
    result = Trackdown::Providers::CloudfrontProvider.locate('8.8.8.8', request: request)

    assert_equal 'Unknown', result.city
  end

  def test_locate_returns_unknown_for_empty_city
    request = mock_cloudfront_request(country: 'US', city: '')
    result = Trackdown::Providers::CloudfrontProvider.locate('8.8.8.8', request: request)

    assert_equal 'Unknown', result.city
  end

  def test_locate_returns_unknown_for_empty_country_code
    request = mock_cloudfront_request(country: '')
    result = Trackdown::Providers::CloudfrontProvider.locate('8.8.8.8', request: request)

    assert_nil result.country_code
    assert_equal 'Unknown', result.country_name
    assert_equal 'Unknown', result.city
    assert_equal '🏳️', result.flag_emoji
  end

  def test_locate_returns_location_result
    request = mock_cloudfront_request
    result = Trackdown::Providers::CloudfrontProvider.locate('8.8.8.8', request: request)

    assert_instance_of Trackdown::LocationResult, result
  end

  def test_locate_upcases_lowercase_country_code
    request = mock_cloudfront_request(country: 'us')
    result = Trackdown::Providers::CloudfrontProvider.locate('8.8.8.8', request: request)

    assert_equal 'US', result.country_code
  end

  def test_locate_with_multiple_countries
    [
      ['FR', 'Paris', '🇫🇷'],
      ['DE', 'Berlin', '🇩🇪'],
      ['JP', 'Tokyo', '🇯🇵'],
      ['BR', 'São Paulo', '🇧🇷']
    ].each do |country_code, city, expected_flag|
      request = mock_cloudfront_request(country: country_code, city: city)
      result = Trackdown::Providers::CloudfrontProvider.locate('1.2.3.4', request: request)

      assert_equal country_code, result.country_code
      assert_equal city, result.city
      assert_equal expected_flag, result.flag_emoji
    end
  end

  # === Header extraction (region name vs code) ===

  def test_locate_extracts_region_name_into_region
    request = mock_cloudfront_request(country: 'US', region: 'California')
    result = Trackdown::Providers::CloudfrontProvider.locate('8.8.8.8', request: request)

    assert_equal 'California', result.region
  end

  def test_locate_extracts_region_code
    request = mock_cloudfront_request(country: 'US', region_code: 'CA')
    result = Trackdown::Providers::CloudfrontProvider.locate('8.8.8.8', request: request)

    assert_equal 'CA', result.region_code
  end

  def test_locate_extracts_timezone_header
    request = mock_cloudfront_request(country: 'US', timezone: 'America/Los_Angeles')
    result = Trackdown::Providers::CloudfrontProvider.locate('8.8.8.8', request: request)

    assert_equal 'America/Los_Angeles', result.timezone
  end

  def test_locate_extracts_latitude_header
    request = mock_cloudfront_request(country: 'US', latitude: '37.7749')
    result = Trackdown::Providers::CloudfrontProvider.locate('8.8.8.8', request: request)

    assert_in_delta 37.7749, result.latitude
  end

  def test_locate_extracts_longitude_header
    request = mock_cloudfront_request(country: 'US', longitude: '-122.4194')
    result = Trackdown::Providers::CloudfrontProvider.locate('8.8.8.8', request: request)

    assert_in_delta(-122.4194, result.longitude)
  end

  def test_locate_extracts_postal_code_header
    request = mock_cloudfront_request(country: 'US', postal_code: '94107')
    result = Trackdown::Providers::CloudfrontProvider.locate('8.8.8.8', request: request)

    assert_equal '94107', result.postal_code
  end

  def test_locate_extracts_metro_code_header
    request = mock_cloudfront_request(country: 'US', metro_code: '807')
    result = Trackdown::Providers::CloudfrontProvider.locate('8.8.8.8', request: request)

    assert_equal '807', result.metro_code
  end

  # CloudFront sends no continent header, so it's derived from the country code and
  # normalized to the same 2-letter code the other providers return.
  def test_derives_continent_code_from_country
    {
      'US' => 'NA', # North America
      'BR' => 'SA', # South America
      'GB' => 'EU', # Europe
      'JP' => 'AS', # Asia
      'ZA' => 'AF', # Africa
      'AU' => 'OC'  # Oceania (the countries gem labels it "Australia")
    }.each do |country_code, expected_continent|
      request = mock_cloudfront_request(country: country_code)
      result = Trackdown::Providers::CloudfrontProvider.locate('8.8.8.8', request: request)

      assert_equal expected_continent, result.continent, "expected #{country_code} to map to #{expected_continent}"
    end
  end

  def test_continent_nil_for_unrecognized_country_code
    request = mock_cloudfront_request(country: 'ZZ')
    result = Trackdown::Providers::CloudfrontProvider.locate('8.8.8.8', request: request)

    assert_nil result.continent
  end

  # Guard against a countries-gem upgrade that renames a continent (e.g. relabeling
  # "Australia" as "Oceania"): every continent name the gem reports must be present
  # in CONTINENT_CODES, otherwise continent would silently derive to nil for those
  # countries. This fails loudly instead.
  def test_continent_codes_cover_every_continent_the_countries_gem_reports
    gem_continents = ISO3166::Country.all.map(&:continent).compact.uniq
    mapped = Trackdown::Providers::CloudfrontProvider::CONTINENT_CODES.keys

    unmapped = gem_continents - mapped
    assert_empty unmapped, "countries gem reports continent name(s) not in CONTINENT_CODES: #{unmapped.inspect}"
  end

  def test_locate_with_all_headers_present
    request = mock_cloudfront_request_with_all_headers
    result = Trackdown::Providers::CloudfrontProvider.locate('8.8.8.8', request: request)

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

  # === Missing / malformed headers return nil ===

  def test_locate_missing_region_returns_nil
    request = mock_cloudfront_request(country: 'US')
    result = Trackdown::Providers::CloudfrontProvider.locate('8.8.8.8', request: request)

    assert_nil result.region
    assert_nil result.region_code
    assert_nil result.timezone
    assert_nil result.latitude
    assert_nil result.longitude
    assert_nil result.postal_code
    assert_nil result.metro_code
  end

  def test_extract_header_empty_string_returns_nil
    request = mock_cloudfront_request(country: 'US')
    request.env['HTTP_CLOUDFRONT_VIEWER_COUNTRY_REGION_NAME'] = ''
    result = Trackdown::Providers::CloudfrontProvider.locate('8.8.8.8', request: request)

    assert_nil result.region
  end

  def test_parse_coordinate_with_zero
    request = mock_cloudfront_request(country: 'GH', city: 'Accra', latitude: '0', longitude: '0')
    result = Trackdown::Providers::CloudfrontProvider.locate('8.8.8.8', request: request)

    assert_in_delta 0.0, result.latitude
    assert_in_delta 0.0, result.longitude
  end

  def test_parse_coordinate_with_non_numeric_string_returns_nil
    request = mock_cloudfront_request(country: 'US', latitude: 'abc', longitude: 'xyz')
    result = Trackdown::Providers::CloudfrontProvider.locate('8.8.8.8', request: request)

    assert_nil result.latitude
    assert_nil result.longitude
  end
end
