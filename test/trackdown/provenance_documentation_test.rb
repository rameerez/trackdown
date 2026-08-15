# frozen_string_literal: true

require "test_helper"

# The docs promise an API. This makes sure the API keeps the promise.
class ProvenanceDocumentationTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  MAXMIND_ACCURACY_URL = "https://support.maxmind.com/knowledge-base/articles/maxmind-geolocation-accuracy"
  CLOUDFLARE_ORIGIN_PULL_URL =
    "https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/"
  CLOUDFRONT_ORIGIN_RESTRICTION_URL =
    "https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-overview.html"

  DOCUMENTED_RESULT_METHODS = %i[
    provider_name provider_source resolved_at estimated?
    available? unavailable? unavailable_reason
    accuracy_radius_in_kilometers accuracy_radius_km accuracy_radius_confidence_percentage
    database_build_epoch database_built_at database_sha256
    source_trust source_was_verified_by_host? host_verified?
    to_h
  ].freeze

  def result
    Trackdown::LocationResult.new('US', 'United States', 'San Francisco', '🇺🇸')
  end

  def test_every_method_the_readme_documents_actually_exists
    DOCUMENTED_RESULT_METHODS.each do |method|
      assert_respond_to result, method
    end
  end

  def test_the_readme_documents_every_method_that_exists
    readme = read("README.md")

    DOCUMENTED_RESULT_METHODS.each do |method|
      assert_includes readme, "result.#{method}".delete_suffix('?'),
                      "README should show how to use ##{method}"
    end
  end

  # Every `only:` list the README shows has to actually work. Aliases like
  # #accuracy_radius_km are readers, not field names, and it would be easy to
  # print one here and hand the reader an ArgumentError.
  def test_every_field_allowlist_the_readme_shows_really_works
    allowlists = read("README.md").scan(/only:\s*%i\[([^\]]*)\]/m).flatten

    refute_empty allowlists, 'the README should show at least one `only:` allowlist'

    allowlists.each do |allowlist|
      fields = allowlist.split(/\s+/).reject(&:empty?).map(&:to_sym)

      assert_equal fields, result.to_h(only: fields).keys
    end
  end

  def test_the_readme_documents_every_unavailable_reason
    readme = read("README.md")

    Trackdown::LocationResult::UNAVAILABLE_REASONS.each do |reason|
      assert_includes readme, ":#{reason}"
    end
  end

  def test_the_readme_documents_every_source_trust_state
    readme = read("README.md")

    Trackdown::LocationResult::SOURCE_TRUSTS.each do |trust|
      assert_includes readme, ":#{trust}"
    end
  end

  def test_the_readme_documents_the_trusted_cdn_path_verifier_and_its_limits
    readme = read("README.md")

    assert_includes readme, 'verify_request_came_through_trusted_cdn_path_with'
    assert_includes readme, CLOUDFLARE_ORIGIN_PULL_URL
    assert_includes readme, CLOUDFRONT_ORIGIN_RESTRICTION_URL
    assert_match(/reports.{0,40}(trust state|this trust)/i, readme,
                 'the README must say Trackdown reports trust rather than acting on it')
  end

  def test_the_readme_sources_the_accuracy_radius_confidence_to_maxmind
    readme = read("README.md")

    assert_includes readme, MAXMIND_ACCURACY_URL
    assert_includes readme, Trackdown::Providers::MaxmindProvider::ACCURACY_RADIUS_CONFIDENCE_PERCENTAGE.to_s
  end

  def test_the_readme_documents_the_unknown_compatibility_path
    readme = read("README.md")

    assert_match(/still return.{0,80}'Unknown'/m, readme)
    assert_match(/available\?/, readme)
  end

  def test_the_changelog_documents_the_unknown_compatibility_path
    changelog = read("CHANGELOG.md")

    assert_match(/still return the display string `"Unknown"`/, changelog)
    assert_includes changelog, 'available?'
  end

  def test_the_changelog_warns_that_to_h_gained_keys
    changelog = read("CHANGELOG.md")

    assert_match(/to_h.{0,200}provenance/m, changelog)
  end

  def test_the_generated_initializer_explains_trusted_cdn_path_verification
    initializer = read("lib/generators/trackdown/templates/trackdown.rb")

    assert_includes initializer, 'verify_request_came_through_trusted_cdn_path_with'
    assert_includes initializer, ':host_verified'
    assert_includes initializer, CLOUDFLARE_ORIGIN_PULL_URL
    assert_includes initializer, CLOUDFRONT_ORIGIN_RESTRICTION_URL
  end

  def test_the_generated_initializer_is_valid_ruby
    initializer_path = File.join(ROOT, 'lib/generators/trackdown/templates/trackdown.rb')

    assert RubyVM::InstructionSequence.compile_file(initializer_path),
           'the generated initializer must at least parse'
  end

  def test_the_gem_still_needs_no_extra_runtime_dependency
    gemspec = read("trackdown.gemspec")

    assert_equal 1, gemspec.scan(/spec\.add_dependency/).length
    assert_includes gemspec, 'spec.add_dependency "countries"'
  end

  private

  def read(relative_path)
    File.read(File.join(ROOT, relative_path))
  end
end
