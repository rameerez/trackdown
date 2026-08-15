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
  CLOUDFRONT_ALL_VIEWER_URL =
    "https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-origin-request-policies.html#managed-origin-request-policy-all-viewer-and-cloudfront"
  CLOUDFLARE_REQUEST_HEADERS_URL =
    "https://developers.cloudflare.com/fundamentals/reference/http-headers/#request-headers"
  RAILS_SECURE_COMPARE_URL =
    "https://api.rubyonrails.org/classes/ActiveSupport/SecurityUtils.html#method-c-secure_compare"
  MAXMIND_MEMORY_READER_URL =
    "https://github.com/maxmind/MaxMind-DB-Reader-ruby/blob/v1.2.0/lib/maxmind/db/memory_reader.rb#L7-L15"
  MAXMIND_FILE_READER_URL =
    "https://github.com/maxmind/MaxMind-DB-Reader-ruby/blob/v1.2.0/lib/maxmind/db/file_reader.rb#L36-L55"
  RUBY_RENAME_URL = "https://docs.ruby-lang.org/en/3.3/File.html#method-c-rename"

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

    assert_includes readme, 'verify_request_came_through_trusted_cloudflare_path_with'
    assert_includes readme, 'verify_request_came_through_trusted_cloudfront_path_with'
    assert_includes readme, CLOUDFLARE_ORIGIN_PULL_URL
    assert_includes readme, CLOUDFRONT_ORIGIN_RESTRICTION_URL
    assert_includes readme, CLOUDFLARE_REQUEST_HEADERS_URL
    assert_includes readme, CLOUDFRONT_ALL_VIEWER_URL
    assert_match(/reports.{0,40}(trust state|this trust)/i, readme,
                 'the README must say Trackdown reports trust rather than acting on it')
  end

  def test_the_readme_shared_secret_example_rejects_missing_credentials
    readme = read("README.md")

    assert_includes readme, "raise 'Missing CloudFront origin secret'"
    assert_includes readme, '!supplied_cloudfront_origin_secret.empty?'
    assert_includes readme, RAILS_SECURE_COMPARE_URL
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

  def test_the_changelog_and_readme_preserve_the_default_to_h_shape
    changelog = read("CHANGELOG.md")
    readme = read("README.md")

    assert_match(/no-argument `to_h` remains.{0,120}same 13 keys/m, changelog)
    assert_includes changelog, 'include_provenance: true'
    assert_match(/no-argument `to_h` is deliberately backward compatible/, readme)
    assert_includes readme, 'result.to_h(include_provenance: true)'
  end

  def test_the_database_race_and_safe_update_are_documented_with_exact_sources
    [read("README.md"), read("CHANGELOG.md")].each do |document|
      assert_includes document, MAXMIND_MEMORY_READER_URL
      assert_includes document, MAXMIND_FILE_READER_URL
      assert_includes document, RUBY_RENAME_URL
    end
  end

  def test_the_generated_initializer_explains_trusted_cdn_path_verification
    initializer = read("lib/generators/trackdown/templates/trackdown.rb")

    assert_includes initializer, 'verify_request_came_through_trusted_cloudflare_path_with'
    assert_includes initializer, 'verify_request_came_through_trusted_cloudfront_path_with'
    assert_includes initializer, ':host_verified'
    assert_includes initializer, CLOUDFLARE_ORIGIN_PULL_URL
    assert_includes initializer, CLOUDFRONT_ORIGIN_RESTRICTION_URL
    assert_includes initializer, CLOUDFLARE_REQUEST_HEADERS_URL
    assert_includes initializer, CLOUDFRONT_ALL_VIEWER_URL
    assert_includes initializer, "raise 'Missing CloudFront origin secret'"
    assert_includes initializer, '!supplied_cloudfront_origin_secret.empty?'
    assert_includes initializer, RAILS_SECURE_COMPARE_URL
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

  # Requiring something the gemspec doesn't declare makes the gem unloadable for
  # anyone who doesn't already happen to have it — and Ruby keeps moving former
  # standard-library gems out of the default set (bigdecimal in 3.4), so a require
  # that works on the machine you wrote it on can still be a LoadError elsewhere.
  # https://docs.ruby-lang.org/en/3.4/standard_library_md.html
  def test_the_gem_only_requires_what_it_declares_or_what_ruby_itself_ships
    declared = Gem::Specification.load(File.join(ROOT, 'trackdown.gemspec'))
                                 .runtime_dependencies.map(&:name)

    required_libraries.each do |library, file|
      next if declared.include?(library)
      next if OPTIONAL_LIBRARIES.include?(library)

      assert shipped_with_ruby?(library),
             "#{file} requires #{library.inspect}, which is neither a declared runtime dependency " \
             "nor part of Ruby #{RUBY_VERSION} itself. Declare it in the gemspec, drop it, or — if it " \
             'is genuinely optional — require it inside a rescue LoadError.'
    end
  end

  # If this ever fails, the dependency contract above is not being checked at all
  # — better to say so loudly than to quietly pass.
  def test_we_can_see_which_gems_ship_with_this_ruby
    assert_includes gems_shipped_with_ruby, 'digest',
                    "Ruby #{RUBY_VERSION} should ship digest; if we cannot see it in " \
                    "#{Gem.default_specifications_dir} we cannot see any default gem"
  end

  def test_every_optional_library_is_required_defensively
    OPTIONAL_LIBRARIES.each do |library|
      files = required_libraries.select { |name, _| name == library }.map(&:last)

      refute_empty files, "#{library} is listed as optional but nothing requires it any more"

      files.each do |file|
        assert_includes File.read(File.join(ROOT, file)), 'rescue LoadError',
                        "#{file} requires the optional #{library} without rescuing LoadError"
      end
    end
  end

  private

  # Documented in the README as optional, and required inside a rescue LoadError.
  OPTIONAL_LIBRARIES = %w[maxmind/db connection_pool].freeze

  def required_libraries
    Dir[File.join(ROOT, 'lib/**/*.rb')].sort.flat_map do |path|
      file = path.delete_prefix("#{ROOT}/")
      File.read(path).scan(/^\s*require ['"]([^'"]+)['"]/).flatten.map { |library| [library, file] }
    end
  end

  # RubyGems is always present; everything else has to be a default gem for this
  # Ruby, which is exactly the check that catches a gem leaving the default set.
  def shipped_with_ruby?(library)
    root = library.split('/').first
    return true if root == 'rubygems'

    gems_shipped_with_ruby.include?(root)
  end

  # Read the default-gem list straight off the Ruby installation. Asking
  # Gem::Specification instead would be wrong under Bundler, which narrows it to
  # the bundle and makes a gem that ships with Ruby look missing.
  # https://docs.ruby-lang.org/en/3.4/standard_library_md.html
  def gems_shipped_with_ruby
    @gems_shipped_with_ruby ||=
      Dir[File.join(Gem.default_specifications_dir, '*.gemspec')]
      .map { |path| File.basename(path).sub(/-[^-]+\.gemspec\z/, '') }
  end

  def read(relative_path)
    File.read(File.join(ROOT, relative_path))
  end
end
