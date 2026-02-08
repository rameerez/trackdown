# frozen_string_literal: true

require "test_helper"

class LocationResultTest < Minitest::Test
  def test_initializes_with_all_attributes
    result = Trackdown::LocationResult.new('US', 'United States', 'San Francisco', '🇺🇸')

    assert_equal 'US', result.country_code
    assert_equal 'United States', result.country_name
    assert_equal 'San Francisco', result.city
    assert_equal '🇺🇸', result.flag_emoji
  end

  def test_country_alias_returns_country_name
    result = Trackdown::LocationResult.new('US', 'United States', 'San Francisco', '🇺🇸')
    assert_equal 'United States', result.country
  end

  def test_emoji_alias_returns_flag_emoji
    result = Trackdown::LocationResult.new('US', 'United States', 'San Francisco', '🇺🇸')
    assert_equal '🇺🇸', result.emoji
  end

  def test_emoji_flag_alias_returns_flag_emoji
    result = Trackdown::LocationResult.new('US', 'United States', 'San Francisco', '🇺🇸')
    assert_equal '🇺🇸', result.emoji_flag
  end

  def test_country_flag_alias_returns_flag_emoji
    result = Trackdown::LocationResult.new('US', 'United States', 'San Francisco', '🇺🇸')
    assert_equal '🇺🇸', result.country_flag
  end

  def test_country_info_returns_iso3166_country_object
    result = Trackdown::LocationResult.new('US', 'United States', 'San Francisco', '🇺🇸')
    country_info = result.country_info

    assert_instance_of ISO3166::Country, country_info
    assert_equal 'US', country_info.alpha2
    assert_equal 'USA', country_info.alpha3
  end

  def test_country_info_returns_nil_for_nil_country_code
    result = Trackdown::LocationResult.new(nil, 'Unknown', 'Unknown', '🏳️')
    assert_nil result.country_info
  end

  def test_to_h_returns_hash_representation
    result = Trackdown::LocationResult.new('GB', 'United Kingdom', 'London', '🇬🇧')
    hash = result.to_h

    assert_equal 'GB', hash[:country_code]
    assert_equal 'United Kingdom', hash[:country_name]
    assert_equal 'London', hash[:city]
    assert_equal '🇬🇧', hash[:flag_emoji]
    assert hash.key?(:country_info)
  end

  def test_to_h_includes_country_info_data
    result = Trackdown::LocationResult.new('FR', 'France', 'Paris', '🇫🇷')
    hash = result.to_h

    refute_empty hash[:country_info]
    assert_equal 'FR', hash[:country_info]['alpha2']
  end

  def test_handles_unknown_country_gracefully
    result = Trackdown::LocationResult.new(nil, 'Unknown', 'Unknown', '🏳️')

    assert_nil result.country_code
    assert_equal 'Unknown', result.country_name
    assert_equal 'Unknown', result.city
    assert_equal '🏳️', result.flag_emoji
    assert_nil result.country_info
  end

  def test_to_h_with_nil_country_code_has_empty_country_info
    result = Trackdown::LocationResult.new(nil, 'Unknown', 'Unknown', '🏳️')
    hash = result.to_h

    assert_equal({}, hash[:country_info])
  end

  # === New fields: region, region_code, continent, timezone, latitude, longitude ===

  def test_initializes_with_all_new_keyword_args
    result = Trackdown::LocationResult.new(
      'US', 'United States', 'San Francisco', '🇺🇸',
      region: 'California',
      region_code: 'CA',
      continent: 'NA',
      timezone: 'America/Los_Angeles',
      latitude: 37.7749,
      longitude: -122.4194
    )

    assert_equal 'California', result.region
    assert_equal 'CA', result.region_code
    assert_equal 'NA', result.continent
    assert_equal 'America/Los_Angeles', result.timezone
    assert_in_delta 37.7749, result.latitude
    assert_in_delta(-122.4194, result.longitude)
  end

  def test_new_fields_default_to_nil_when_not_provided
    result = Trackdown::LocationResult.new('US', 'United States', 'San Francisco', '🇺🇸')

    assert_nil result.region
    assert_nil result.region_code
    assert_nil result.continent
    assert_nil result.timezone
    assert_nil result.latitude
    assert_nil result.longitude
  end

  def test_to_h_includes_all_six_new_fields
    result = Trackdown::LocationResult.new(
      'DE', 'Germany', 'Berlin', '🇩🇪',
      region: 'Berlin',
      region_code: 'BE',
      continent: 'EU',
      timezone: 'Europe/Berlin',
      latitude: 52.5200,
      longitude: 13.4050
    )
    hash = result.to_h

    assert_equal 'Berlin', hash[:region]
    assert_equal 'BE', hash[:region_code]
    assert_equal 'EU', hash[:continent]
    assert_equal 'Europe/Berlin', hash[:timezone]
    assert_in_delta 52.5200, hash[:latitude]
    assert_in_delta 13.4050, hash[:longitude]
  end

  def test_to_h_includes_nil_new_fields_when_not_set
    result = Trackdown::LocationResult.new('US', 'United States', 'NYC', '🇺🇸')
    hash = result.to_h

    assert hash.key?(:region)
    assert hash.key?(:region_code)
    assert hash.key?(:continent)
    assert hash.key?(:timezone)
    assert hash.key?(:latitude)
    assert hash.key?(:longitude)

    assert_nil hash[:region]
    assert_nil hash[:region_code]
    assert_nil hash[:continent]
    assert_nil hash[:timezone]
    assert_nil hash[:latitude]
    assert_nil hash[:longitude]
  end

  def test_combination_some_new_fields_set_others_nil
    result = Trackdown::LocationResult.new(
      'JP', 'Japan', 'Tokyo', '🇯🇵',
      region: 'Tokyo',
      timezone: 'Asia/Tokyo',
      latitude: 35.6762
    )

    assert_equal 'Tokyo', result.region
    assert_nil result.region_code
    assert_nil result.continent
    assert_equal 'Asia/Tokyo', result.timezone
    assert_in_delta 35.6762, result.latitude
    assert_nil result.longitude
  end

  def test_empty_string_values_for_new_fields
    result = Trackdown::LocationResult.new(
      'US', 'United States', 'NYC', '🇺🇸',
      region: '',
      region_code: '',
      continent: '',
      timezone: ''
    )

    assert_equal '', result.region
    assert_equal '', result.region_code
    assert_equal '', result.continent
    assert_equal '', result.timezone
  end

  def test_very_long_string_values_for_new_fields
    long_string = 'A' * 1000
    result = Trackdown::LocationResult.new(
      'US', 'United States', 'NYC', '🇺🇸',
      region: long_string,
      timezone: long_string
    )

    assert_equal long_string, result.region
    assert_equal long_string, result.timezone
  end

  def test_latitude_positive_float
    result = Trackdown::LocationResult.new('AU', 'Australia', 'Sydney', '🇦🇺', latitude: 33.8688)
    assert_in_delta 33.8688, result.latitude
  end

  def test_latitude_negative_float
    result = Trackdown::LocationResult.new('AR', 'Argentina', 'Buenos Aires', '🇦🇷', latitude: -34.6037)
    assert_in_delta(-34.6037, result.latitude)
  end

  def test_latitude_zero
    result = Trackdown::LocationResult.new('EC', 'Ecuador', 'Quito', '🇪🇨', latitude: 0.0)
    assert_in_delta 0.0, result.latitude
  end

  def test_latitude_boundary_positive_90
    result = Trackdown::LocationResult.new('NO', 'Norway', 'North Pole', '🇳🇴', latitude: 90.0)
    assert_in_delta 90.0, result.latitude
  end

  def test_latitude_boundary_negative_90
    result = Trackdown::LocationResult.new('AQ', 'Antarctica', 'South Pole', '🇦🇶', latitude: -90.0)
    assert_in_delta(-90.0, result.latitude)
  end

  def test_longitude_positive_float
    result = Trackdown::LocationResult.new('JP', 'Japan', 'Tokyo', '🇯🇵', longitude: 139.6917)
    assert_in_delta 139.6917, result.longitude
  end

  def test_longitude_negative_float
    result = Trackdown::LocationResult.new('US', 'United States', 'SF', '🇺🇸', longitude: -122.4194)
    assert_in_delta(-122.4194, result.longitude)
  end

  def test_longitude_zero
    result = Trackdown::LocationResult.new('GH', 'Ghana', 'Accra', '🇬🇭', longitude: 0.0)
    assert_in_delta 0.0, result.longitude
  end

  def test_longitude_boundary_positive_180
    result = Trackdown::LocationResult.new('FJ', 'Fiji', 'Suva', '🇫🇯', longitude: 180.0)
    assert_in_delta 180.0, result.longitude
  end

  def test_longitude_boundary_negative_180
    result = Trackdown::LocationResult.new('FJ', 'Fiji', 'Suva', '🇫🇯', longitude: -180.0)
    assert_in_delta(-180.0, result.longitude)
  end

  def test_backward_compatibility_positional_args_only
    result = Trackdown::LocationResult.new('US', 'United States', 'San Francisco', '🇺🇸')

    assert_equal 'US', result.country_code
    assert_equal 'United States', result.country_name
    assert_equal 'San Francisco', result.city
    assert_equal '🇺🇸', result.flag_emoji
    assert_nil result.region
    assert_nil result.region_code
    assert_nil result.continent
    assert_nil result.timezone
    assert_nil result.latitude
    assert_nil result.longitude
  end

  def test_latitude_and_longitude_both_set
    result = Trackdown::LocationResult.new(
      'GB', 'United Kingdom', 'London', '🇬🇧',
      latitude: 51.5074,
      longitude: -0.1278
    )

    assert_in_delta 51.5074, result.latitude
    assert_in_delta(-0.1278, result.longitude)
  end

  def test_integer_latitude_longitude_stored_as_given
    result = Trackdown::LocationResult.new(
      'GH', 'Ghana', 'Accra', '🇬🇭',
      latitude: 5,
      longitude: 0
    )

    assert_equal 5, result.latitude
    assert_equal 0, result.longitude
  end
end
