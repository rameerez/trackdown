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
end
