# frozen_string_literal: true

require 'test_helper'

class LocationResultTest < Minitest::Test
  def test_readers_and_aliases
    result = Trackdown::LocationResult.new('US', 'United States', 'Mountain View', '🇺🇸')
    assert_equal 'US', result.country_code
    assert_equal 'United States', result.country_name
    assert_equal 'United States', result.country
    assert_equal 'Mountain View', result.city
    assert_equal '🇺🇸', result.flag_emoji
    assert_equal '🇺🇸', result.emoji
    assert_equal '🇺🇸', result.emoji_flag
    assert_equal '🇺🇸', result.country_flag
  end

  def test_country_info_present
    result = Trackdown::LocationResult.new('US', 'United States', 'Mountain View', '🇺🇸')
    info = result.country_info
    refute_nil info
    assert_equal 'US', info.alpha2
    assert_includes ['United States of America', 'United States'], info.common_name || info.iso_short_name || info.iso_long_name
  end

  def test_country_info_nil_when_no_country_code
    result = Trackdown::LocationResult.new(nil, 'Unknown', 'Unknown', '🏳️')
    assert_nil result.country_info
  end

  def test_to_h_output
    result = Trackdown::LocationResult.new('US', 'United States', 'Mountain View', '🇺🇸')
    h = result.to_h
    assert_equal 'US', h[:country_code]
    assert_equal 'United States', h[:country_name]
    assert_equal 'Mountain View', h[:city]
    assert_equal '🇺🇸', h[:flag_emoji]
    assert_kind_of Hash, h[:country_info]
  end

  def test_to_h_output_without_country
    result = Trackdown::LocationResult.new(nil, 'Unknown', 'Unknown', '🏳️')
    h = result.to_h
    assert_nil result.country_info
    # Uses safe navigation and returns {} in to_h when country_info is nil
    assert_equal({}, h[:country_info])
  end
end