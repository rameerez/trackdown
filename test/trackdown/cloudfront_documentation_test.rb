# frozen_string_literal: true

require "test_helper"

class CloudfrontDocumentationTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  AWS_VIEWER_LOCATION_URL =
    "https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html" \
    "#cloudfront-headers-viewer-location"
  AWS_MANAGED_POLICY_URL =
    "https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-origin-request-policies.html" \
    "#managed-origin-request-policy-all-viewer-and-cloudfront"
  AWS_CUSTOM_HEADER_URL =
    "https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/add-origin-custom-headers.html"
  AWS_ORIGIN_RESTRICTION_URL =
    "https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-overview.html"
  CLOUDFLARE_CONNECTING_IP_URL =
    "https://developers.cloudflare.com/fundamentals/reference/http-headers/#cf-connecting-ip"
  CLOUDFLARE_ORIGIN_SECURITY_URL =
    "https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/"
  RFC_3986_ENCODING_URL = "https://www.rfc-editor.org/rfc/rfc3986#section-2.1"
  RFC_5870_COORDINATE_URL = "https://www.rfc-editor.org/rfc/rfc5870#section-3.4.2"

  CLOUDFRONT_HEADERS = %w[
    CloudFront-Viewer-Country
    CloudFront-Viewer-City
    CloudFront-Viewer-Country-Region-Name
    CloudFront-Viewer-Country-Region
    CloudFront-Viewer-Latitude
    CloudFront-Viewer-Longitude
    CloudFront-Viewer-Time-Zone
    CloudFront-Viewer-Postal-Code
    CloudFront-Viewer-Metro-Code
    CloudFront-Viewer-Address
  ].freeze

  def test_readme_documents_complete_cloudfront_setup_and_trust_boundary
    readme = read("README.md")

    CLOUDFRONT_HEADERS.each { |header| assert_includes readme, header }
    [
      AWS_VIEWER_LOCATION_URL,
      AWS_MANAGED_POLICY_URL,
      AWS_CUSTOM_HEADER_URL,
      AWS_ORIGIN_RESTRICTION_URL,
      CLOUDFLARE_CONNECTING_IP_URL,
      CLOUDFLARE_ORIGIN_SECURITY_URL,
      RFC_3986_ENCODING_URL,
      RFC_5870_COORDINATE_URL
    ].each { |source_url| assert_includes readme, source_url }

    assert_includes readme, "custom least-privilege policy"
    assert_includes readme, "Prevent direct access to the origin"
    assert_includes readme, "both Cloudflare and CloudFront header families match"
    assert_includes readme, "missing, malformed, or mismatching address"
    refute_match(/CloudFront[^\n]*zero config/i, readme)
  end

  def test_generated_initializer_documents_cloudfront_and_exact_sources
    template = read("lib/generators/trackdown/templates/trackdown.rb")

    assert_includes template, "# :cloudfront"
    assert_includes template, "CloudFront-Viewer-Address"
    assert_includes template, AWS_VIEWER_LOCATION_URL
    assert_includes template, AWS_MANAGED_POLICY_URL
    assert_includes template, AWS_CUSTOM_HEADER_URL
    assert_includes template, AWS_ORIGIN_RESTRICTION_URL
    assert_includes template, "custom least-privilege policy"
  end

  def test_install_message_exposes_cloudfront_setup_and_origin_security
    generator = read("lib/generators/trackdown/install_generator.rb")

    assert_includes generator, "Option 2: Amazon CloudFront"
    assert_includes generator, "CloudFront-Viewer-Address"
    assert_includes generator, AWS_VIEWER_LOCATION_URL
    assert_includes generator, AWS_ORIGIN_RESTRICTION_URL
    assert_includes generator, CLOUDFLARE_ORIGIN_SECURITY_URL
    assert_includes generator, "Option 4: Auto"
    assert_includes generator, "one IP-corroborated CDN provider"
  end

  def test_changelog_records_validation_security_and_primary_sources
    changelog = read("CHANGELOG.md")

    [
      AWS_VIEWER_LOCATION_URL,
      AWS_MANAGED_POLICY_URL,
      AWS_CUSTOM_HEADER_URL,
      AWS_ORIGIN_RESTRICTION_URL,
      CLOUDFLARE_CONNECTING_IP_URL,
      CLOUDFLARE_ORIGIN_SECURITY_URL,
      RFC_3986_ENCODING_URL,
      RFC_5870_COORDINATE_URL
    ].each { |source_url| assert_includes changelog, source_url }

    assert_includes changelog, "fail closed"
    assert_includes changelog, "non-finite or out-of-range"
  end

  def test_gem_metadata_and_public_api_docs_name_every_provider
    gemspec = read("trackdown.gemspec")
    public_api = read("lib/trackdown.rb")
    locator = read("lib/trackdown/ip_locator.rb")

    %w[Cloudflare CloudFront MaxMind].each do |provider|
      assert_includes gemspec, provider
    end
    assert_includes public_api, "required for CDN providers"
    assert_includes locator, "for CDN providers"
  end

  private

  def read(relative_path)
    File.read(File.join(ROOT, relative_path))
  end
end
