# frozen_string_literal: true

require "test_helper"

class AutoProviderTest < Minitest::Test
  def test_available_returns_true_when_cloudflare_available
    request = mock_cloudflare_request

    assert Trackdown::Providers::AutoProvider.available?(request: request)
  end

  def test_available_returns_true_when_maxmind_available
    Trackdown.configuration.database_path = '/fake/path.mmdb'

    File.stub :exist?, true do
      assert Trackdown::Providers::AutoProvider.available?
    end
  end

  def test_available_returns_false_when_no_providers_available
    # No request (Cloudflare unavailable) and no database (MaxMind unavailable)
    Trackdown.configuration.database_path = '/nonexistent/path.mmdb'

    refute Trackdown::Providers::AutoProvider.available?
  end

  def test_locate_tries_cloudflare_first
    request = mock_cloudflare_request(country: 'GB', city: 'London')
    expected_result = Trackdown::LocationResult.new('GB', 'United Kingdom', 'London', '🇬🇧')

    # Cloudflare should be called
    Trackdown::Providers::CloudflareProvider.expects(:available?).with(request: request).returns(true)
    Trackdown::Providers::CloudflareProvider.expects(:locate).with('1.2.3.4', request: request).returns(expected_result)

    # MaxMind should NOT be called
    Trackdown::Providers::MaxmindProvider.expects(:available?).never
    Trackdown::Providers::MaxmindProvider.expects(:locate).never

    result = Trackdown::Providers::AutoProvider.locate('1.2.3.4', request: request)

    assert_equal 'GB', result.country_code
  end

  def test_locate_falls_back_to_maxmind_when_cloudflare_unavailable
    request = mock_request_without_cloudflare
    expected_result = Trackdown::LocationResult.new('US', 'United States', 'Mountain View', '🇺🇸')

    # Cloudflare should be tried but not available
    Trackdown::Providers::CloudflareProvider.expects(:available?).with(request: request).returns(false)

    # MaxMind should be used
    Trackdown::Providers::MaxmindProvider.expects(:available?).with(request: request).returns(true)
    Trackdown::Providers::MaxmindProvider.expects(:locate).with('8.8.8.8', request: request).returns(expected_result)

    result = Trackdown::Providers::AutoProvider.locate('8.8.8.8', request: request)

    assert_equal 'US', result.country_code
  end

  def test_locate_returns_unknown_when_no_providers_available
    Trackdown.configuration.database_path = '/nonexistent/path.mmdb'

    # Should not raise - should return Unknown gracefully
    result = Trackdown::Providers::AutoProvider.locate('8.8.8.8')

    assert_nil result.country_code
    assert_equal 'Unknown', result.country_name
    assert_equal 'Unknown', result.city
    assert_equal '🏳️', result.flag_emoji
  end

  def test_gracefully_handles_no_providers_without_crashing
    Trackdown.configuration.database_path = '/nonexistent/path.mmdb'

    # The key test: should not raise an error, just return Unknown
    # This is tested in test_locate_returns_unknown_when_no_providers_available
    # but let's also verify it doesn't crash when called multiple times
    results = []

    # Should not raise even when called multiple times
    3.times do
      results << Trackdown::Providers::AutoProvider.locate('8.8.8.8')
    end

    # All results should be Unknown
    results.each do |result|
      assert_equal 'Unknown', result.country_name
      assert_equal 'Unknown', result.city
      assert_nil result.country_code
    end
  end

  def test_cloudflare_takes_precedence_when_both_available
    request = mock_cloudflare_request(country: 'FR', city: 'Paris')
    cf_result = Trackdown::LocationResult.new('FR', 'France', 'Paris', '🇫🇷')

    Trackdown.configuration.database_path = '/fake/path.mmdb'

    File.stub :exist?, true do
      # Cloudflare available
      Trackdown::Providers::CloudflareProvider.expects(:available?).with(request: request).returns(true)
      Trackdown::Providers::CloudflareProvider.expects(:locate).with('1.2.3.4', request: request).returns(cf_result)

      # MaxMind should not be checked
      Trackdown::Providers::MaxmindProvider.expects(:available?).never

      result = Trackdown::Providers::AutoProvider.locate('1.2.3.4', request: request)

      assert_equal 'FR', result.country_code
      assert_equal 'Paris', result.city
    end
  end

  def test_without_request_object_uses_maxmind
    # No request object provided - should skip Cloudflare and use MaxMind
    expected_result = Trackdown::LocationResult.new('US', 'United States', 'Seattle', '🇺🇸')
    Trackdown.configuration.database_path = '/fake/path.mmdb'

    File.stub :exist?, true do
      Trackdown::Providers::CloudflareProvider.expects(:available?).with(request: nil).returns(false)
      Trackdown::Providers::MaxmindProvider.expects(:available?).with(request: nil).returns(true)
      Trackdown::Providers::MaxmindProvider.expects(:locate).with('8.8.8.8', request: nil).returns(expected_result)

      result = Trackdown::Providers::AutoProvider.locate('8.8.8.8')

      assert_equal 'US', result.country_code
    end
  end
end
