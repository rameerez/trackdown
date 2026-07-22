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

  # --- IP Mismatch Detection Tests ---
  # When there's an upstream proxy before Cloudflare, CF-Connecting-IP will contain
  # the proxy's IP, not the real client. The geo headers will be wrong.

  def test_uses_cloudflare_when_cf_connecting_ip_matches
    # CF-Connecting-IP matches the IP we're looking up - Cloudflare headers are valid
    client_ip = '104.255.87.245'
    request = mock_cloudflare_request_with_matching_ip(ip: client_ip, country: 'GB', city: 'London')
    cf_result = Trackdown::LocationResult.new('GB', 'United Kingdom', 'London', '🇬🇧')

    Trackdown::Providers::CloudflareProvider.expects(:available?).with(request: request).returns(true)
    Trackdown::Providers::CloudflareProvider.expects(:locate).with(client_ip, request: request).returns(cf_result)
    Trackdown::Providers::MaxmindProvider.expects(:locate).never

    result = Trackdown::Providers::AutoProvider.locate(client_ip, request: request)

    assert_equal 'GB', result.country_code
    assert_equal 'London', result.city
  end

  def test_uses_cloudflare_when_ipv6_formats_are_equivalent
    # Same IPv6 address represented with different formatting.
    client_ip = '2001:0db8:0000:0000:0000:0000:0000:0001'
    request = Object.new
    env = {
      'HTTP_CF_IPCOUNTRY' => 'DE',
      'HTTP_CF_IPCITY' => 'Berlin',
      'HTTP_CF_CONNECTING_IP' => '2001:db8::1'
    }
    request.define_singleton_method(:env) { env }
    cf_result = Trackdown::LocationResult.new('DE', 'Germany', 'Berlin', '🇩🇪')

    Trackdown::Providers::CloudflareProvider.expects(:available?).with(request: request).returns(true)
    Trackdown::Providers::CloudflareProvider.expects(:locate).with(client_ip, request: request).returns(cf_result)
    Trackdown::Providers::MaxmindProvider.expects(:locate).never

    result = Trackdown::Providers::AutoProvider.locate(client_ip, request: request)

    assert_equal 'DE', result.country_code
    assert_equal 'Berlin', result.city
  end

  def test_uses_cloudflare_when_ipv4_mapped_ipv6_matches
    # Cloudflare may emit IPv4-mapped IPv6 in some network paths.
    client_ip = '203.0.113.9'
    request = Object.new
    env = {
      'HTTP_CF_IPCOUNTRY' => 'US',
      'HTTP_CF_IPCITY' => 'Denver',
      'HTTP_CF_CONNECTING_IP' => '::ffff:203.0.113.9'
    }
    request.define_singleton_method(:env) { env }
    cf_result = Trackdown::LocationResult.new('US', 'United States', 'Denver', '🇺🇸')

    Trackdown::Providers::CloudflareProvider.expects(:available?).with(request: request).returns(true)
    Trackdown::Providers::CloudflareProvider.expects(:locate).with(client_ip, request: request).returns(cf_result)
    Trackdown::Providers::MaxmindProvider.expects(:locate).never

    result = Trackdown::Providers::AutoProvider.locate(client_ip, request: request)

    assert_equal 'US', result.country_code
    assert_equal 'Denver', result.city
  end

  def test_falls_back_to_maxmind_when_cf_connecting_ip_differs
    # Simulates an upstream proxy before Cloudflare (e.g., rameerezapi)
    # The real client is in India, but CF-Connecting-IP shows the proxy in Ashburn
    client_ip = '104.255.87.245'  # Real client IP
    proxy_ip = '34.204.24.48'     # Proxy's IP that Cloudflare saw (in Ashburn)

    request = mock_cloudflare_request_with_proxy(
      proxy_ip: proxy_ip,
      proxy_country: 'US',
      proxy_city: 'Ashburn'
    )

    # MaxMind should geolocate the real client IP correctly
    maxmind_result = Trackdown::LocationResult.new('IN', 'India', 'Mumbai', '🇮🇳')
    Trackdown.configuration.database_path = '/fake/path.mmdb'

    File.stub :exist?, true do
      Trackdown::Providers::CloudflareProvider.expects(:available?).with(request: request).returns(true)
      # Cloudflare locate should NOT be called because IPs don't match
      Trackdown::Providers::CloudflareProvider.expects(:locate).never
      Trackdown::Providers::MaxmindProvider.expects(:available?).with(request: request).returns(true)
      Trackdown::Providers::MaxmindProvider.expects(:locate).with(client_ip, request: request).returns(maxmind_result)

      result = Trackdown::Providers::AutoProvider.locate(client_ip, request: request)

      # Should return the correct location from MaxMind, not Ashburn from Cloudflare
      assert_equal 'IN', result.country_code
      assert_equal 'Mumbai', result.city
    end
  end

  def test_uses_cloudflare_when_no_cf_connecting_ip_header
    # If CF-Connecting-IP is not present, assume Cloudflare headers are valid
    # (this is the legacy behavior for apps that don't have this header)
    request = mock_cloudflare_request(country: 'DE', city: 'Berlin')
    cf_result = Trackdown::LocationResult.new('DE', 'Germany', 'Berlin', '🇩🇪')

    Trackdown::Providers::CloudflareProvider.expects(:available?).with(request: request).returns(true)
    Trackdown::Providers::CloudflareProvider.expects(:locate).with('8.8.8.8', request: request).returns(cf_result)
    Trackdown::Providers::MaxmindProvider.expects(:locate).never

    result = Trackdown::Providers::AutoProvider.locate('8.8.8.8', request: request)

    assert_equal 'DE', result.country_code
  end

  # --- CloudFront edge-header integration ---

  def test_available_true_with_cloudfront_headers
    request = mock_cloudfront_request(country: 'US')
    assert Trackdown::Providers::AutoProvider.available?(request: request)
  end

  def test_uses_cloudfront_when_cloudflare_absent
    request = mock_cloudfront_request(country: 'CA', city: 'Toronto')
    result = Trackdown::Providers::AutoProvider.locate('8.8.8.8', request: request)

    assert_equal 'CA', result.country_code
    assert_equal 'Toronto', result.city
  end

  def test_uses_cloudfront_when_viewer_address_matches
    client_ip = '203.0.113.9'
    request = mock_cloudfront_request_with_matching_ip(ip: client_ip, country: 'US', city: 'Denver')
    result = Trackdown::Providers::AutoProvider.locate(client_ip, request: request)

    assert_equal 'US', result.country_code
    assert_equal 'Denver', result.city
  end

  def test_cloudflare_takes_precedence_over_cloudfront
    # A request carrying both CDNs' headers should resolve via Cloudflare (higher priority)
    request = Object.new
    env = {
      'HTTP_CF_IPCOUNTRY' => 'GB', 'HTTP_CF_IPCITY' => 'London',
      'HTTP_CLOUDFRONT_VIEWER_COUNTRY' => 'US', 'HTTP_CLOUDFRONT_VIEWER_CITY' => 'New York'
    }
    request.define_singleton_method(:env) { env }

    result = Trackdown::Providers::AutoProvider.locate('8.8.8.8', request: request)

    assert_equal 'GB', result.country_code
    assert_equal 'London', result.city
  end

  def test_falls_back_to_maxmind_when_cloudfront_viewer_address_differs
    # Simulates an upstream proxy before CloudFront: Viewer-Address shows the proxy,
    # not the real client, so CloudFront's geo would be wrong.
    client_ip = '104.255.87.245'
    proxy_ip = '34.204.24.48'
    request = mock_cloudfront_request_with_proxy(proxy_ip: proxy_ip, proxy_country: 'US', proxy_city: 'Ashburn')

    maxmind_result = Trackdown::LocationResult.new('IN', 'India', 'Mumbai', '🇮🇳')
    Trackdown.configuration.database_path = '/fake/path.mmdb'

    File.stub :exist?, true do
      # CloudFront locate must NOT be called because the IPs don't match
      Trackdown::Providers::CloudfrontProvider.expects(:locate).never
      Trackdown::Providers::MaxmindProvider.expects(:available?).with(request: request).returns(true)
      Trackdown::Providers::MaxmindProvider.expects(:locate).with(client_ip, request: request).returns(maxmind_result)

      result = Trackdown::Providers::AutoProvider.locate(client_ip, request: request)

      assert_equal 'IN', result.country_code
      assert_equal 'Mumbai', result.city
    end
  end
end
