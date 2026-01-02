# frozen_string_literal: true

require "test_helper"

class IpLocatorTest < Minitest::Test
  def test_locate_validates_ip
    Trackdown::IpValidator.expects(:validate!).with('8.8.8.8')

    Trackdown.configuration.provider = :cloudflare
    request = mock_cloudflare_request
    Trackdown::Providers::CloudflareProvider.stub :locate, Trackdown::LocationResult.new('US', 'United States', 'San Francisco', '🇺🇸') do
      Trackdown::IpLocator.locate('8.8.8.8', request: request)
    end
  end

  def test_locate_rejects_private_ip_when_configured
    Trackdown.configuration.reject_private_ips = true

    error = assert_raises(Trackdown::IpValidator::InvalidIpError) do
      Trackdown::IpLocator.locate('192.168.1.1')
    end

    assert_match(/Private IP addresses are not allowed/, error.message)
  end

  def test_locate_allows_private_ip_when_not_configured
    Trackdown.configuration.reject_private_ips = false
    Trackdown.configuration.provider = :cloudflare

    request = mock_cloudflare_request
    result = Trackdown::LocationResult.new('US', 'United States', 'Unknown', '🇺🇸')

    Trackdown::Providers::CloudflareProvider.stub :locate, result do
      # Should not raise an error
      returned_result = Trackdown::IpLocator.locate('192.168.1.1', request: request)
      assert_equal 'US', returned_result.country_code
    end
  end

  def test_locate_selects_cloudflare_provider_when_configured
    Trackdown.configuration.provider = :cloudflare
    request = mock_cloudflare_request
    expected_result = Trackdown::LocationResult.new('GB', 'United Kingdom', 'London', '🇬🇧')

    Trackdown::Providers::CloudflareProvider.expects(:locate).with('1.2.3.4', request: request).returns(expected_result)

    result = Trackdown::IpLocator.locate('1.2.3.4', request: request)

    assert_equal 'GB', result.country_code
  end

  def test_locate_selects_maxmind_provider_when_configured
    Trackdown.configuration.provider = :maxmind
    expected_result = Trackdown::LocationResult.new('FR', 'France', 'Paris', '🇫🇷')

    Trackdown::Providers::MaxmindProvider.expects(:locate).with('5.6.7.8', request: nil).returns(expected_result)

    result = Trackdown::IpLocator.locate('5.6.7.8')

    assert_equal 'FR', result.country_code
  end

  def test_locate_selects_auto_provider_by_default
    # Default provider should be :auto
    expected_result = Trackdown::LocationResult.new('US', 'United States', 'Seattle', '🇺🇸')

    Trackdown::Providers::AutoProvider.expects(:locate).with('8.8.8.8', request: nil).returns(expected_result)

    result = Trackdown::IpLocator.locate('8.8.8.8')

    assert_equal 'US', result.country_code
  end

  def test_locate_delegates_to_provider
    Trackdown.configuration.provider = :auto
    request = mock_cloudflare_request
    expected_result = Trackdown::LocationResult.new('DE', 'Germany', 'Berlin', '🇩🇪')

    Trackdown::Providers::AutoProvider.expects(:locate).with('9.9.9.9', request: request).returns(expected_result)

    result = Trackdown::IpLocator.locate('9.9.9.9', request: request)

    assert_instance_of Trackdown::LocationResult, result
    assert_equal 'DE', result.country_code
    assert_equal 'Berlin', result.city
  end

  def test_locate_passes_request_to_provider
    Trackdown.configuration.provider = :cloudflare
    request = mock_cloudflare_request(country: 'JP', city: 'Tokyo')

    # Verify request object is passed through
    Trackdown::Providers::CloudflareProvider.expects(:locate)
      .with('1.2.3.4', request: request)
      .returns(Trackdown::LocationResult.new('JP', 'Japan', 'Tokyo', '🇯🇵'))

    Trackdown::IpLocator.locate('1.2.3.4', request: request)
  end

  def test_locate_raises_error_for_unknown_provider
    Trackdown.configuration.instance_variable_set(:@provider, :unknown)

    error = assert_raises(Trackdown::Error) do
      Trackdown::IpLocator.locate('8.8.8.8')
    end

    assert_match(/Unknown provider/, error.message)
  end
end
