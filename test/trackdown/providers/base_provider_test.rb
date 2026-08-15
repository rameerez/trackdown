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

  def test_provider_name_raises_not_implemented_error
    error = assert_raises(NotImplementedError) do
      Trackdown::Providers::BaseProvider.provider_name
    end

    assert_match(/must implement .provider_name/, error.message)
  end

  def test_provider_source_raises_not_implemented_error
    error = assert_raises(NotImplementedError) do
      Trackdown::Providers::BaseProvider.provider_source
    end

    assert_match(/must implement .provider_source/, error.message)
  end

  def test_every_shipped_provider_names_itself_after_its_configuration_symbol
    assert_equal :cloudflare, Trackdown::Providers::CloudflareProvider.provider_name
    assert_equal :cloudfront, Trackdown::Providers::CloudfrontProvider.provider_name
    assert_equal :maxmind, Trackdown::Providers::MaxmindProvider.provider_name

    names = [Trackdown::Providers::CloudflareProvider, Trackdown::Providers::CloudfrontProvider,
             Trackdown::Providers::MaxmindProvider].map(&:provider_name)

    assert_equal Trackdown::Configuration::VALID_PROVIDERS - [:auto], names
  end

  def test_auto_has_no_name_of_its_own
    assert_nil Trackdown::Providers::AutoProvider.provider_name
    assert_nil Trackdown::Providers::AutoProvider.provider_source
  end

  def test_every_shipped_provider_names_its_source
    assert_equal :cloudflare_request_headers, Trackdown::Providers::CloudflareProvider.provider_source
    assert_equal :cloudfront_request_headers, Trackdown::Providers::CloudfrontProvider.provider_source
    assert_equal :maxmind_local_database, Trackdown::Providers::MaxmindProvider.provider_source
  end

  def test_get_country_name_survives_a_countries_gem_that_blows_up
    ISO3166::Country.stub(:new, ->(_code) { raise 'the countries gem exploded' }) do
      assert_equal 'Unknown', Trackdown::Providers::BaseProvider.send(:get_country_name, 'US')
    end
  end

  def test_request_provenance_is_unverified_without_a_host_verifier
    provenance = Trackdown::Providers::CloudflareProvider.request_provenance(mock_request)

    assert_equal :cloudflare, provenance[:provider_name]
    assert_equal :cloudflare_request_headers, provenance[:provider_source]
    assert_equal :unverified, provenance[:source_trust]
  end
end
