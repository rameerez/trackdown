# frozen_string_literal: true

require "test_helper"
require "rack/mock"
require "rack/request"

class CloudfrontProviderAdversarialTest < Minitest::Test
  def test_header_constants_match_rack_names_for_every_supported_cloudfront_field
    # AWS source for the exact CloudFront header names:
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html#cloudfront-headers-viewer-location
    # Rack source for the HTTP_ request-environment convention:
    # https://github.com/rack/rack/blob/main/SPEC.rdoc#http_-headers
    expected_headers = {
      COUNTRY_HEADER: "HTTP_CLOUDFRONT_VIEWER_COUNTRY",
      CITY_HEADER: "HTTP_CLOUDFRONT_VIEWER_CITY",
      REGION_HEADER: "HTTP_CLOUDFRONT_VIEWER_COUNTRY_REGION_NAME",
      REGION_CODE_HEADER: "HTTP_CLOUDFRONT_VIEWER_COUNTRY_REGION",
      LATITUDE_HEADER: "HTTP_CLOUDFRONT_VIEWER_LATITUDE",
      LONGITUDE_HEADER: "HTTP_CLOUDFRONT_VIEWER_LONGITUDE",
      TIMEZONE_HEADER: "HTTP_CLOUDFRONT_VIEWER_TIME_ZONE",
      POSTAL_CODE_HEADER: "HTTP_CLOUDFRONT_VIEWER_POSTAL_CODE",
      METRO_CODE_HEADER: "HTTP_CLOUDFRONT_VIEWER_METRO_CODE"
    }

    expected_headers.each do |constant, rack_header|
      assert_equal rack_header, Trackdown::Providers::CloudfrontProvider.const_get(constant)
    end
  end

  def test_extracts_every_field_from_a_real_rack_request
    # Rack requires ordinary request headers to be exposed through HTTP_* environment keys:
    # https://github.com/rack/rack/blob/main/SPEC.rdoc#http_-headers
    env = Rack::MockRequest.env_for(
      "/",
      "HTTP_CLOUDFRONT_VIEWER_COUNTRY" => "US",
      "HTTP_CLOUDFRONT_VIEWER_CITY" => "Seattle",
      "HTTP_CLOUDFRONT_VIEWER_COUNTRY_REGION_NAME" => "Washington",
      "HTTP_CLOUDFRONT_VIEWER_COUNTRY_REGION" => "WA",
      "HTTP_CLOUDFRONT_VIEWER_LATITUDE" => "47.6062",
      "HTTP_CLOUDFRONT_VIEWER_LONGITUDE" => "-122.3321",
      "HTTP_CLOUDFRONT_VIEWER_TIME_ZONE" => "America/Los_Angeles",
      "HTTP_CLOUDFRONT_VIEWER_POSTAL_CODE" => "98101",
      "HTTP_CLOUDFRONT_VIEWER_METRO_CODE" => "819"
    )

    result = Trackdown::Providers::CloudfrontProvider.locate(
      "203.0.113.9",
      request: Rack::Request.new(env)
    )

    assert_equal(
      {
        country_code: "US",
        city: "Seattle",
        region: "Washington",
        region_code: "WA",
        continent: "NA",
        timezone: "America/Los_Angeles",
        latitude: 47.6062,
        longitude: -122.3321,
        postal_code: "98101",
        metro_code: "819"
      },
      result.to_h.slice(
        :country_code, :city, :region, :region_code, :continent,
        :timezone, :latitude, :longitude, :postal_code, :metro_code
      )
    )
  end

  def test_country_city_and_optional_fields_follow_aws_availability_rules
    # AWS says city, metro code, and postal code might be unavailable for some IPs, and
    # the extended location fields are omitted for requests originating in the AWS network:
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html#cloudfront-headers-viewer-location
    request = mock_cloudfront_request(country: "DE", city: nil)

    result = Trackdown::Providers::CloudfrontProvider.locate("203.0.113.9", request: request)

    assert_equal "DE", result.country_code
    assert_equal "Unknown", result.city
    assert_nil result.region
    assert_nil result.region_code
    assert_nil result.latitude
    assert_nil result.longitude
    assert_nil result.timezone
    assert_nil result.postal_code
    assert_nil result.metro_code
  end

  def test_preserves_cloudfront_region_codes_up_to_three_characters
    # AWS defines the region value as an ISO 3166-2 subdivision code of up to three characters:
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html#cloudfront-headers-viewer-location
    request = mock_cloudfront_request(country: "GB", region: "England", region_code: "ENG")

    result = Trackdown::Providers::CloudfrontProvider.locate("203.0.113.9", request: request)

    assert_equal "England", result.region
    assert_equal "ENG", result.region_code
  end

  def test_parses_coordinate_boundaries_as_floats
    # AWS defines latitude and longitude as approximate viewer coordinates:
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html#cloudfront-headers-viewer-location
    [
      ["90.0", "180.0", 90.0, 180.0],
      ["-90.0", "-180.0", -90.0, -180.0],
      ["+0.0", "-0.0", 0.0, -0.0]
    ].each do |latitude, longitude, expected_latitude, expected_longitude|
      request = mock_cloudfront_request(country: "GH", latitude: latitude, longitude: longitude)
      result = Trackdown::Providers::CloudfrontProvider.locate("203.0.113.9", request: request)

      assert_equal expected_latitude, result.latitude
      assert_equal expected_longitude, result.longitude
    end
  end

  def test_rejects_every_non_finite_or_non_numeric_coordinate_spelling
    # AWS defines these fields as geographic latitude/longitude values. BigDecimal
    # lets Trackdown reject huge exponents before converting them to Float:
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html#cloudfront-headers-viewer-location
    # https://docs.ruby-lang.org/en/3.3/BigDecimal.html
    ["NaN", "Infinity", "-Infinity", "1e1000", "-1e1000", "1.2.3", "37N", "", " "].each do |coordinate|
      request = mock_cloudfront_request(country: "US", latitude: coordinate, longitude: coordinate)
      result = Trackdown::Providers::CloudfrontProvider.locate("203.0.113.9", request: request)

      assert_nil result.latitude, "expected #{coordinate.inspect} latitude to be rejected"
      assert_nil result.longitude, "expected #{coordinate.inspect} longitude to be rejected"
    end
  end

  def test_non_string_header_values_fail_closed_without_raising
    # Rack's CGI-style environment specifies header values as strings. Treat values
    # outside that contract as unavailable rather than invoking arbitrary coercions:
    # https://github.com/rack/rack/blob/main/SPEC.rdoc#http_-headers
    request = mock_cloudfront_request(country: Object.new)

    refute Trackdown::Providers::CloudfrontProvider.available?(request: request)

    result = Trackdown::Providers::CloudfrontProvider.locate("203.0.113.9", request: request)
    assert_nil result.country_code
    assert_equal "Unknown", result.country_name

    request = mock_cloudfront_request(
      country: "US",
      city: Object.new,
      region: 123,
      latitude: 47,
      longitude: Object.new
    )

    result = Trackdown::Providers::CloudfrontProvider.locate("203.0.113.9", request: request)
    assert_equal "Unknown", result.city
    assert_nil result.region
    assert_nil result.latitude
    assert_nil result.longitude
  end

  def test_rejects_finite_coordinates_outside_wgs84_bounds
    # RFC 5870 requires WGS-84 latitude to stay within -90..90 and longitude
    # within -180..180; coordinates outside those bounds are invalid:
    # https://www.rfc-editor.org/rfc/rfc5870#section-3.4.2
    [
      ["90.000001", "0"],
      ["-90.000001", "0"],
      ["0", "180.000001"],
      ["0", "-180.000001"]
    ].each do |latitude, longitude|
      request = mock_cloudfront_request(country: "US", latitude: latitude, longitude: longitude)
      result = Trackdown::Providers::CloudfrontProvider.locate("203.0.113.9", request: request)

      if latitude == "0"
        assert_equal 0.0, result.latitude
        assert_nil result.longitude, "expected #{longitude.inspect} longitude to be rejected"
      else
        assert_nil result.latitude, "expected #{latitude.inspect} latitude to be rejected"
        assert_equal 0.0, result.longitude
      end
    end
  end

  def test_derives_all_seven_continent_codes
    # CloudFront emits an ISO 3166-1 alpha-2 country code but no continent header:
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html#cloudfront-headers-viewer-location
    {
      "ZA" => "AF",
      "AQ" => "AN",
      "JP" => "AS",
      "AU" => "OC",
      "DE" => "EU",
      "CA" => "NA",
      "BR" => "SA"
    }.each do |country_code, expected_continent|
      request = mock_cloudfront_request(country: country_code)
      result = Trackdown::Providers::CloudfrontProvider.locate("203.0.113.9", request: request)

      assert_equal expected_continent, result.continent
    end
  end

  def test_every_iso_country_has_a_name_flag_country_info_and_continent
    ISO3166::Country.all.each do |country|
      request = mock_cloudfront_request(country: country.alpha2)
      result = Trackdown::Providers::CloudfrontProvider.locate("203.0.113.9", request: request)

      assert_equal country.alpha2, result.country_code
      refute_equal "Unknown", result.country_name, country.alpha2
      refute_equal "🏳️", result.flag_emoji, country.alpha2
      assert_equal country.alpha2, result.country_info.alpha2
      assert_includes %w[AF AN AS EU NA OC SA], result.continent, country.alpha2
    end
  end

  def test_countries_lookup_failure_does_not_crash_the_provider
    request = mock_cloudfront_request(country: "US")

    ISO3166::Country.stub(:new, ->(_country_code) { raise "countries lookup failed" }) do
      result = Trackdown::Providers::CloudfrontProvider.locate("203.0.113.9", request: request)

      assert_nil result.country_code
      assert_equal "Unknown", result.country_name
      assert_equal "Unknown", result.city
      assert_equal "🏳️", result.flag_emoji
      assert_nil result.continent
    end
  end

  def test_percent_decodes_non_ascii_city_names
    # AWS explicitly percent-encodes non-ASCII characters in viewer-location values:
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html#cloudfront-headers-viewer-location
    request = mock_cloudfront_request(country: "BR", city: "S%C3%A3o Paulo".b)

    result = Trackdown::Providers::CloudfrontProvider.locate("203.0.113.9", request: request)

    assert_equal "São Paulo", result.city
    assert_equal Encoding::UTF_8, result.city.encoding
  end

  def test_percent_decodes_non_ascii_region_names
    # AWS explicitly percent-encodes non-ASCII characters in viewer-location values:
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html#cloudfront-headers-viewer-location
    request = mock_cloudfront_request(country: "CA", region: "Qu%C3%A9bec".b, region_code: "QC")

    result = Trackdown::Providers::CloudfrontProvider.locate("203.0.113.9", request: request)

    assert_equal "Québec", result.region
    assert_equal Encoding::UTF_8, result.region.encoding
  end

  def test_percent_decoding_does_not_apply_form_urlencoded_plus_semantics
    # RFC 3986 percent encoding does not define "+" as a space (that convention belongs to
    # application/x-www-form-urlencoded):
    # https://www.rfc-editor.org/rfc/rfc3986#section-2.1
    request = mock_cloudfront_request(country: "CH", city: "A+B")

    result = Trackdown::Providers::CloudfrontProvider.locate("203.0.113.9", request: request)

    assert_equal "A+B", result.city
  end

  def test_percent_decodes_every_textual_location_field
    # AWS applies RFC 3986 percent encoding to non-ASCII viewer-location header values:
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html#cloudfront-headers-viewer-location
    # RFC 3986 defines a percent-encoded octet as "%" followed by exactly two hex digits:
    # https://www.rfc-editor.org/rfc/rfc3986#section-2.1
    request = mock_cloudfront_request(
      country: "CA",
      city: "Montr%C3%A9al".b,
      region: "Qu%C3%A9bec".b,
      region_code: "%51%43".b,
      timezone: "America%2FToronto".b,
      postal_code: "H2Y%201C6".b,
      metro_code: "%38%30%37".b
    )

    result = Trackdown::Providers::CloudfrontProvider.locate("203.0.113.9", request: request)

    assert_equal "Montréal", result.city
    assert_equal "Québec", result.region
    assert_equal "QC", result.region_code
    assert_equal "America/Toronto", result.timezone
    assert_equal "H2Y 1C6", result.postal_code
    assert_equal "807", result.metro_code
    [result.city, result.region, result.region_code, result.timezone, result.postal_code, result.metro_code].each do |value|
      assert_equal Encoding::UTF_8, value.encoding
      assert_predicate value, :valid_encoding?
    end
  end

  def test_malformed_percent_encoding_fails_closed_without_raising
    # RFC 3986 permits only two hexadecimal digits after each percent sign:
    # https://www.rfc-editor.org/rfc/rfc3986#section-2.1
    request = mock_cloudfront_request(
      country: "US",
      city: "Bad%ZZ",
      region: "%C3%28".b,
      timezone: "America%2",
      postal_code: "%"
    )

    result = Trackdown::Providers::CloudfrontProvider.locate("203.0.113.9", request: request)

    assert_equal "Unknown", result.city
    assert_nil result.region
    assert_nil result.timezone
    assert_nil result.postal_code
  end

  def test_invalid_country_headers_do_not_make_the_provider_available
    # AWS defines this value as an ISO 3166-1 alpha-2 country code:
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html#cloudfront-headers-viewer-location
    [" ", "USA", "ZZ", "1!", "ß"].each do |country_code|
      request = mock_cloudfront_request(country: country_code)

      refute(
        Trackdown::Providers::CloudfrontProvider.available?(request: request),
        "expected #{country_code.inspect} not to identify CloudFront as available"
      )
    end
  end

  def test_public_locate_api_uses_explicit_cloudfront_provider_end_to_end
    # AWS source for the input header semantics used by this public-API test:
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html#cloudfront-headers-viewer-location
    Trackdown.configuration.provider = :cloudfront
    request = mock_cloudfront_request_with_all_headers

    result = Trackdown.locate("203.0.113.9", request: request)

    assert_instance_of Trackdown::LocationResult, result
    assert_equal "US", result.country_code
    assert_equal "San Francisco", result.city
    assert_equal "California", result.region
    assert_equal "CA", result.region_code
    assert_equal "NA", result.continent
    assert_equal "America/Los_Angeles", result.timezone
    assert_equal 37.7749, result.latitude
    assert_equal(-122.4194, result.longitude)
    assert_equal "94107", result.postal_code
    assert_equal "807", result.metro_code
  end
end

class CloudfrontAutoProviderAdversarialTest < Minitest::Test
  def setup
    super
    reset_auto_provider_warnings
  end

  def teardown
    reset_auto_provider_warnings
    super
  end

  def test_matching_ipv4_viewer_address_uses_cloudfront_without_maxmind
    # AWS documents CloudFront-Viewer-Address as the viewer IP plus source port:
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html#cloudfront-headers-viewer-location
    request = mock_cloudfront_request(
      country: "US",
      city: "Denver",
      viewer_address: "203.0.113.9:46532"
    )
    Trackdown::Providers::MaxmindProvider.expects(:available?).never
    Trackdown::Providers::MaxmindProvider.expects(:locate).never

    result = Trackdown::Providers::AutoProvider.locate("203.0.113.9", request: request)

    assert_equal "Denver", result.city
  end

  def test_non_string_cloudflare_corroborator_fails_closed_without_raising
    # Rack's request-header values are strings; a non-string value is malformed and
    # cannot corroborate the target IP:
    # https://github.com/rack/rack/blob/main/SPEC.rdoc#http_-headers
    request = mock_cloudflare_request(country: "US", city: "Spoofed")
    request.env["HTTP_CF_CONNECTING_IP"] = Object.new
    Trackdown.configuration.database_path = "/nonexistent/path.mmdb"

    result = nil
    _stdout, stderr = capture_io do
      result = Trackdown::Providers::AutoProvider.locate("203.0.113.9", request: request)
    end

    assert_nil result.country_code
    assert_equal "Unknown", result.country_name
    assert_includes stderr, "Cannot verify Cloudflare geolocation"
    assert_includes stderr, "CF-Connecting-IP is malformed"
    assert_includes stderr, "trying the next available provider"
  end

  def test_equivalent_expanded_ipv6_viewer_address_uses_cloudfront
    # AWS defines the header as an IP address plus source port, while Ruby's IPAddr supplies
    # semantic IPv6 normalization across expanded and compressed spellings:
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html#cloudfront-headers-viewer-location
    # https://docs.ruby-lang.org/en/3.3/IPAddr.html
    request = mock_cloudfront_request(
      country: "DE",
      city: "Berlin",
      viewer_address: "2001:0db8:0000:0000:0000:0000:0000:0001:46532"
    )
    Trackdown::Providers::MaxmindProvider.expects(:locate).never

    result = Trackdown::Providers::AutoProvider.locate("2001:db8::1", request: request)

    assert_equal "Berlin", result.city
  end

  def test_bracketed_ipv6_viewer_address_uses_cloudfront
    # Brackets are the RFC 3986 IP-literal representation; accepting them keeps parsing
    # robust if an intermediary serializes the address and port as an authority value:
    # https://www.rfc-editor.org/rfc/rfc3986#section-3.2.2
    request = mock_cloudfront_request(
      country: "JP",
      city: "Tokyo",
      viewer_address: "[2001:db8::1]:46532"
    )
    Trackdown::Providers::MaxmindProvider.expects(:locate).never

    result = Trackdown::Providers::AutoProvider.locate("2001:0db8:0:0:0:0:0:1", request: request)

    assert_equal "Tokyo", result.city
  end

  def test_ipv4_mapped_ipv6_viewer_address_matches_native_ipv4
    # Ruby's IPAddr#native converts IPv4-mapped IPv6 to its native IPv4 representation:
    # https://docs.ruby-lang.org/en/3.3/IPAddr.html#method-i-native
    request = mock_cloudfront_request(
      country: "US",
      city: "Denver",
      viewer_address: "::ffff:203.0.113.9:46532"
    )
    Trackdown::Providers::MaxmindProvider.expects(:locate).never

    result = Trackdown::Providers::AutoProvider.locate("203.0.113.9", request: request)

    assert_equal "Denver", result.city
  end

  def test_cloudflare_mismatch_then_matching_cloudfront_uses_cloudfront_before_maxmind
    request = mock_cloudfront_request(
      country: "CA",
      city: "Toronto",
      viewer_address: "203.0.113.9:46532"
    )
    request.env["HTTP_CF_IPCOUNTRY"] = "US"
    request.env["HTTP_CF_IPCITY"] = "Ashburn"
    request.env["HTTP_CF_CONNECTING_IP"] = "198.51.100.7"
    Trackdown::Providers::MaxmindProvider.expects(:available?).never
    Trackdown::Providers::MaxmindProvider.expects(:locate).never

    result = nil
    _stdout, stderr = capture_io do
      result = Trackdown::Providers::AutoProvider.locate("203.0.113.9", request: request)
    end

    assert_equal "CA", result.country_code
    assert_equal "Toronto", result.city
    assert_includes stderr, "CF-Connecting-IP"
    refute_includes stderr, "Falling back to MaxMind"
  end

  def test_cloudfront_mismatch_falls_back_to_maxmind_for_ipv6
    request = mock_cloudfront_request(
      country: "US",
      city: "Ashburn",
      viewer_address: "2001:db8::2:46532"
    )
    maxmind_result = Trackdown::LocationResult.new("DE", "Germany", "Berlin", "🇩🇪")
    Trackdown::Providers::MaxmindProvider.expects(:available?).with(request: request).returns(true)
    Trackdown::Providers::MaxmindProvider.expects(:locate)
      .with("2001:db8::1", request: request)
      .returns(maxmind_result)

    result = nil
    _stdout, _stderr = capture_io do
      result = Trackdown::Providers::AutoProvider.locate("2001:db8::1", request: request)
    end

    assert_equal "DE", result.country_code
    assert_equal "Berlin", result.city
  end

  def test_malformed_viewer_address_falls_back_to_maxmind
    request = mock_cloudfront_request(country: "US", viewer_address: "not-an-ip:46532")
    maxmind_result = Trackdown::LocationResult.new("FR", "France", "Paris", "🇫🇷")
    Trackdown::Providers::MaxmindProvider.expects(:available?).with(request: request).returns(true)
    Trackdown::Providers::MaxmindProvider.expects(:locate)
      .with("203.0.113.9", request: request)
      .returns(maxmind_result)

    result = nil
    _stdout, _stderr = capture_io do
      result = Trackdown::Providers::AutoProvider.locate("203.0.113.9", request: request)
    end

    assert_equal "FR", result.country_code
  end

  def test_every_malformed_viewer_address_form_falls_back_to_maxmind
    # AWS defines the value as an IP address followed by a source port; values without
    # both components do not satisfy the documented contract:
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html#cloudfront-headers-viewer-location
    # RFC 6335 defines the 16-bit port range and identifies zero as reserved:
    # https://www.rfc-editor.org/rfc/rfc6335#section-6
    [
      "203.0.113.9",
      "203.0.113.9:",
      "203.0.113.9:not-a-port",
      "203.0.113.9:0",
      "203.0.113.9:65536",
      "203.0.113.9:99999999999",
      ":46532",
      "[2001:db8::1]",
      "[2001:db8::1]:not-a-port",
      "[2001:db8::1]:65536"
    ].each do |viewer_address|
      reset_auto_provider_warnings
      request = mock_cloudfront_request(country: "US", viewer_address: viewer_address)
      maxmind_result = Trackdown::LocationResult.new("NL", "Netherlands", "Amsterdam", "🇳🇱")
      Trackdown::Providers::MaxmindProvider.expects(:available?).with(request: request).returns(true)
      Trackdown::Providers::MaxmindProvider.expects(:locate)
        .with("203.0.113.9", request: request)
        .returns(maxmind_result)

      result = nil
      _stdout, _stderr = capture_io do
        result = Trackdown::Providers::AutoProvider.locate("203.0.113.9", request: request)
      end

      assert_equal "NL", result.country_code, viewer_address
    end
  end

  def test_missing_viewer_address_falls_back_to_maxmind_in_auto_mode
    # AWS documents Viewer-Address as the viewer IP plus source port, and the managed policy
    # recommended by this PR includes it. Without that corroborating header, :auto cannot prove
    # that the geolocation headers describe the target IP:
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html#cloudfront-headers-viewer-location
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-origin-request-policies.html#managed-origin-request-policy-all-viewer-and-cloudfront
    request = mock_cloudfront_request(country: "IT", city: "Rome", viewer_address: nil)
    maxmind_result = Trackdown::LocationResult.new("PT", "Portugal", "Lisbon", "🇵🇹")
    Trackdown::Providers::MaxmindProvider.expects(:available?).with(request: request).returns(true)
    Trackdown::Providers::MaxmindProvider.expects(:locate)
      .with("203.0.113.9", request: request)
      .returns(maxmind_result)

    result = nil
    _stdout, stderr = capture_io do
      result = Trackdown::Providers::AutoProvider.locate("203.0.113.9", request: request)
    end

    assert_equal "PT", result.country_code
    assert_equal "Lisbon", result.city
    assert_includes stderr, "CloudFront-Viewer-Address is missing"
    assert_includes stderr, "trying the next available provider"
  end

  def test_no_provider_warning_lists_cloudfront_as_a_configuration_option
    Trackdown.configuration.database_path = "/nonexistent/path.mmdb"

    _stdout, stderr = capture_io do
      Trackdown::Providers::AutoProvider.locate("203.0.113.9")
    end

    assert_includes stderr, "Cloudflare"
    assert_includes stderr, "CloudFront"
    assert_includes stderr, "MaxMind"
  end

  def test_invalid_cloudfront_country_falls_through_to_maxmind
    # AWS defines CloudFront-Viewer-Country as an ISO 3166-1 alpha-2 value:
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html#cloudfront-headers-viewer-location
    request = mock_cloudfront_request(
      country: "ZZ",
      city: "Spoofed",
      viewer_address: "203.0.113.9:46532"
    )
    maxmind_result = Trackdown::LocationResult.new("PT", "Portugal", "Lisbon", "🇵🇹")
    Trackdown::Providers::MaxmindProvider.expects(:available?).with(request: request).returns(true)
    Trackdown::Providers::MaxmindProvider.expects(:locate)
      .with("203.0.113.9", request: request)
      .returns(maxmind_result)

    result = Trackdown::Providers::AutoProvider.locate("203.0.113.9", request: request)

    assert_equal "PT", result.country_code
    assert_equal "Lisbon", result.city
  end

  def test_viewer_supplied_cloudflare_headers_cannot_override_authentic_cloudfront_headers
    # The exact managed policy recommended by this PR forwards *all viewer headers* and also
    # adds the listed CloudFront headers:
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-origin-request-policies.html#managed-origin-request-policy-all-viewer-and-cloudfront
    # CloudFront overwrites viewer-supplied CloudFront header values with its own values, but
    # ordinary CF-* headers remain viewer headers under that policy:
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/lambda-at-edge-function-restrictions.html#lambda-at-edge-restrictions-cloudfront-headers
    # CloudFront also adds X-Amz-Cf-Id to origin requests, so including it makes this fixture
    # model the documented origin-request shape; this header is not treated as authentication:
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/RequestAndResponseBehaviorCustomOrigin.html#request-custom-headers-behavior
    request = mock_cloudfront_request(
      country: "US",
      city: "Seattle",
      viewer_address: "203.0.113.9:46532"
    )
    request.env["HTTP_X_AMZ_CF_ID"] = "cloudfront-generated-request-id"
    request.env["HTTP_CF_IPCOUNTRY"] = "GB"
    request.env["HTTP_CF_IPCITY"] = "Spoofed London"
    Trackdown::Providers::MaxmindProvider.expects(:locate).never

    result = Trackdown::Providers::AutoProvider.locate("203.0.113.9", request: request)

    assert_equal "US", result.country_code
    assert_equal "Seattle", result.city
  end

  def test_matching_headers_from_both_cdns_fail_closed_as_ambiguous
    # AWS's managed policy forwards all viewer headers, including viewer-supplied CF-* names:
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-origin-request-policies.html#managed-origin-request-policy-all-viewer-and-cloudfront
    # Cloudflare says CF-Connecting-IP is authentic only on its own edge-to-origin traffic;
    # after another CDN forwards a viewer-supplied value, header shape alone is insufficient:
    # https://developers.cloudflare.com/fundamentals/reference/http-headers/#cf-connecting-ip
    request = mock_cloudfront_request(
      country: "US",
      city: "Seattle",
      viewer_address: "203.0.113.9:46532"
    )
    request.env["HTTP_CF_IPCOUNTRY"] = "GB"
    request.env["HTTP_CF_IPCITY"] = "Spoofed London"
    request.env["HTTP_CF_CONNECTING_IP"] = "203.0.113.9"
    maxmind_result = Trackdown::LocationResult.new("PT", "Portugal", "Lisbon", "🇵🇹")
    Trackdown::Providers::CloudflareProvider.expects(:locate).never
    Trackdown::Providers::CloudfrontProvider.expects(:locate).never
    Trackdown::Providers::MaxmindProvider.expects(:available?).with(request: request).returns(true)
    Trackdown::Providers::MaxmindProvider.expects(:locate)
      .with("203.0.113.9", request: request)
      .returns(maxmind_result)

    result = nil
    _stdout, stderr = capture_io do
      result = Trackdown::Providers::AutoProvider.locate("203.0.113.9", request: request)
    end

    assert_equal "PT", result.country_code
    assert_equal "Lisbon", result.city
    assert_includes stderr, "Both Cloudflare and CloudFront headers match"
    assert_includes stderr, "cannot choose safely"
  end

  def test_ambiguous_edge_headers_return_unknown_without_maxmind
    # The managed policy forwards all viewer headers, so matching header families cannot
    # authenticate which CDN supplied the geolocation values:
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-origin-request-policies.html#managed-origin-request-policy-all-viewer-and-cloudfront
    Trackdown.configuration.database_path = "/nonexistent/path.mmdb"
    request = mock_cloudfront_request(
      country: "US",
      city: "Seattle",
      viewer_address: "203.0.113.9:46532"
    )
    request.env["HTTP_CF_IPCOUNTRY"] = "GB"
    request.env["HTTP_CF_IPCITY"] = "Spoofed London"
    request.env["HTTP_CF_CONNECTING_IP"] = "203.0.113.9"

    result = nil
    _stdout, stderr = capture_io do
      result = Trackdown::Providers::AutoProvider.locate("203.0.113.9", request: request)
    end

    assert_nil result.country_code
    assert_equal "Unknown", result.country_name
    assert_equal "Unknown", result.city
    assert_equal "🏳️", result.flag_emoji
    assert_includes stderr, "Both Cloudflare and CloudFront headers match"
    assert_includes stderr, "No IP geolocation provider available"
  end

  def test_explicit_cloudfront_provider_uses_secured_headers_without_auto_ip_guard
    # AWS requires the origin trust boundary to be enforced by the deployment; once that
    # is done, explicit :cloudfront selection intentionally bypasses :auto ambiguity rules:
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-overview.html
    Trackdown.configuration.provider = :cloudfront
    request = mock_cloudfront_request(
      country: "JP",
      city: "Tokyo",
      viewer_address: "198.51.100.10:46532"
    )

    result = Trackdown.locate("203.0.113.9", request: request)

    assert_equal "JP", result.country_code
    assert_equal "Tokyo", result.city
  end

  def test_auto_is_unavailable_for_uncorroborated_edge_headers_without_maxmind
    # Both official edge contracts provide a client-IP corroborator. :auto must not
    # advertise uncorroborated country headers as usable providers:
    # https://developers.cloudflare.com/fundamentals/reference/http-headers/#cf-connecting-ip
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html#cloudfront-headers-viewer-location
    Trackdown.configuration.database_path = "/nonexistent/path.mmdb"

    refute Trackdown::Providers::AutoProvider.available?(
      request: mock_cloudflare_request(country: "US", city: "Seattle")
    )
    refute Trackdown::Providers::AutoProvider.available?(
      request: mock_cloudfront_request(country: "US", city: "Seattle", viewer_address: nil)
    )
  end

  private
end
