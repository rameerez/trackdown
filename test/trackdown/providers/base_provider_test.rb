# frozen_string_literal: true

require "test_helper"

class BaseProviderTest < Minitest::Test
  def test_available_raises_not_implemented_error
    error = assert_raises(NotImplementedError) do
      Trackdown::Providers::BaseProvider.available?
    end

    assert_match(/must implement .available\?/, error.message)
  end

  def test_locate_raises_not_implemented_error
    error = assert_raises(NotImplementedError) do
      Trackdown::Providers::BaseProvider.locate('8.8.8.8')
    end

    assert_match(/must implement .locate/, error.message)
  end

  def test_get_emoji_flag_converts_us_to_flag
    flag = Trackdown::Providers::BaseProvider.send(:get_emoji_flag, 'US')
    assert_equal '🇺🇸', flag
  end

  def test_get_emoji_flag_converts_gb_to_flag
    flag = Trackdown::Providers::BaseProvider.send(:get_emoji_flag, 'GB')
    assert_equal '🇬🇧', flag
  end

  def test_get_emoji_flag_converts_fr_to_flag
    flag = Trackdown::Providers::BaseProvider.send(:get_emoji_flag, 'FR')
    assert_equal '🇫🇷', flag
  end

  def test_get_emoji_flag_returns_white_flag_for_nil
    flag = Trackdown::Providers::BaseProvider.send(:get_emoji_flag, nil)
    assert_equal '🏳️', flag
  end

  def test_get_country_name_returns_name_for_valid_code
    name = Trackdown::Providers::BaseProvider.send(:get_country_name, 'US')
    assert_equal 'United States of America', name
  end

  def test_get_country_name_returns_name_for_gb
    name = Trackdown::Providers::BaseProvider.send(:get_country_name, 'GB')
    assert_equal 'United Kingdom of Great Britain and Northern Ireland', name
  end

  def test_get_country_name_returns_unknown_for_nil
    name = Trackdown::Providers::BaseProvider.send(:get_country_name, nil)
    assert_equal 'Unknown', name
  end

  def test_get_country_name_returns_unknown_for_invalid_code
    name = Trackdown::Providers::BaseProvider.send(:get_country_name, 'ZZ')
    assert_equal 'Unknown', name
  end

  def test_get_country_name_returns_unknown_for_xx
    name = Trackdown::Providers::BaseProvider.send(:get_country_name, 'XX')
    assert_equal 'Unknown', name
  end
end
