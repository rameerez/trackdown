# frozen_string_literal: true

require "test_helper"

# End-to-end: can a caller answer, from one result object, *how* it was produced?
class ProvenanceTest < Minitest::Test
  def setup
    super
    reset_auto_provider_warnings
  end

  def teardown
    reset_auto_provider_warnings
    super
  end

  VIEWER_IP = '203.0.113.9'

  # A Cloudflare request :auto will accept: every location header, plus the
  # CF-Connecting-IP that corroborates the address we're asking about.
  def cloudflare_request(ip = VIEWER_IP)
    mock_cloudflare_request_with_all_headers(connecting_ip: ip)
  end

  # The CloudFront equivalent, corroborated by CloudFront-Viewer-Address.
  def cloudfront_request(ip = VIEWER_IP)
    mock_cloudfront_request_with_all_headers(viewer_address: "#{ip}:46532")
  end

  # === Cloudflare says it was Cloudflare ===

  def test_cloudflare_names_itself_and_its_source
    result = Trackdown.locate('203.0.113.9', request: cloudflare_request)

    assert_equal :cloudflare, result.provider_name
    assert_equal :cloudflare_request_headers, result.provider_source
  end

  def test_cloudflare_records_when_it_resolved
    before = Time.now.utc
    result = Trackdown.locate('203.0.113.9', request: cloudflare_request)

    assert_kind_of Time, result.resolved_at
    assert_operator result.resolved_at, :>=, before
    assert_operator result.resolved_at, :<=, Time.now.utc
  end

  def test_cloudflare_is_available_and_estimated
    result = Trackdown.locate('203.0.113.9', request: cloudflare_request)

    assert_predicate result, :available?
    refute_predicate result, :unavailable?
    assert_predicate result, :estimated?
    assert_nil result.unavailable_reason
  end

  def test_cloudflare_invents_no_accuracy_or_database_values
    result = Trackdown.locate('203.0.113.9', request: cloudflare_request)

    assert_nil result.accuracy_radius_in_kilometers
    assert_nil result.accuracy_radius_confidence_percentage
    assert_nil result.database_build_epoch
    assert_nil result.database_sha256
    assert_nil result.database_built_at
  end

  # === CloudFront says it was CloudFront ===

  def test_cloudfront_names_itself_and_its_source
    result = Trackdown.locate('203.0.113.9', request: cloudfront_request)

    assert_equal :cloudfront, result.provider_name
    assert_equal :cloudfront_request_headers, result.provider_source
  end

  def test_cloudfront_invents_no_accuracy_or_database_values
    result = Trackdown.locate('203.0.113.9', request: cloudfront_request)

    assert_nil result.accuracy_radius_in_kilometers
    assert_nil result.accuracy_radius_confidence_percentage
    assert_nil result.database_build_epoch
    assert_nil result.database_sha256
  end

  def test_cloudfront_is_available_and_estimated
    result = Trackdown.locate('203.0.113.9', request: cloudfront_request)

    assert_predicate result, :available?
    assert_predicate result, :estimated?
  end

  # === Source trust is never read out of the headers ===

  def test_cloudflare_headers_alone_are_unverified
    result = Trackdown.locate('203.0.113.9', request: cloudflare_request)

    assert_equal :unverified, result.source_trust
    refute_predicate result, :source_was_verified_by_host?
  end

  def test_a_complete_and_corroborated_cloudflare_request_is_still_unverified
    # Every location header, plus a CF-Connecting-IP that matches the IP we asked
    # about. Convincing — and still not proof the request reached us through
    # Cloudflare, because anyone can send these to an unprotected origin.
    request = mock_cloudflare_request_with_all_headers(connecting_ip: '203.0.113.9')
    result = Trackdown.locate('203.0.113.9', request: request)

    assert_equal :cloudflare, result.provider_name
    assert_equal :unverified, result.source_trust
    refute_predicate result, :source_was_verified_by_host?
  end

  def test_a_corroborated_cloudfront_request_is_still_unverified
    request = mock_cloudfront_request_with_matching_ip(ip: '203.0.113.9')
    result = Trackdown.locate('203.0.113.9', request: request)

    assert_equal :cloudfront, result.provider_name
    assert_equal :unverified, result.source_trust
  end

  def test_the_host_can_vouch_for_a_cloudflare_request
    verify_trusted_cdn_path_with_header
    request = cloudflare_request
    request.env['HTTP_X_ORIGIN_SECRET'] = 'shared-secret'

    result = Trackdown.locate('203.0.113.9', request: request)

    assert_equal :host_verified, result.source_trust
    assert_predicate result, :source_was_verified_by_host?
    assert_predicate result, :host_verified?
  end

  def test_the_host_can_decline_to_vouch_for_a_cloudflare_request
    verify_trusted_cdn_path_with_header
    request = cloudflare_request
    request.env['HTTP_X_ORIGIN_SECRET'] = 'the-wrong-secret'

    result = Trackdown.locate('203.0.113.9', request: request)

    assert_equal :unverified, result.source_trust
    refute_predicate result, :source_was_verified_by_host?
  end

  def test_trusted_and_unverified_cloudflare_requests_are_distinguishable
    verify_trusted_cdn_path_with_header

    trusted = cloudflare_request
    trusted.env['HTTP_X_ORIGIN_SECRET'] = 'shared-secret'
    unverified = cloudflare_request

    trusted_result = Trackdown.locate('203.0.113.9', request: trusted)
    unverified_result = Trackdown.locate('203.0.113.9', request: unverified)

    assert_equal :host_verified, trusted_result.source_trust
    assert_equal :unverified, unverified_result.source_trust
    # Same location, different provenance — that's the whole point.
    assert_equal trusted_result.country_code, unverified_result.country_code
  end

  def test_the_host_can_vouch_for_a_cloudfront_request
    verify_trusted_cdn_path_with_header(provider_name: :cloudfront)
    request = cloudfront_request
    request.env['HTTP_X_ORIGIN_SECRET'] = 'shared-secret'

    result = Trackdown.locate('203.0.113.9', request: request)

    assert_equal :host_verified, result.source_trust
  end

  def test_a_trusted_cloudfront_path_cannot_vouch_for_cloudflare_headers
    # CloudFront's AllViewerAndCloudFrontHeaders policy forwards every viewer
    # header, so a viewer can supply CF-* names. A valid CloudFront origin secret
    # must therefore never authenticate a Cloudflare result:
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-origin-request-policies.html#managed-origin-request-policy-all-viewer-and-cloudfront
    verify_trusted_cdn_path_with_header(provider_name: :cloudfront)
    request = cloudflare_request
    request.env['HTTP_X_ORIGIN_SECRET'] = 'shared-secret'

    result = Trackdown.locate('203.0.113.9', request: request)

    assert_equal :cloudflare_request_headers, result.provider_source
    assert_equal :unverified, result.source_trust
  end

  def test_a_trusted_cloudflare_path_cannot_vouch_for_cloudfront_headers
    verify_trusted_cdn_path_with_header(provider_name: :cloudflare)
    request = cloudfront_request
    request.env['HTTP_X_ORIGIN_SECRET'] = 'shared-secret'

    result = Trackdown.locate('203.0.113.9', request: request)

    assert_equal :cloudfront_request_headers, result.provider_source
    assert_equal :unverified, result.source_trust
  end

  def test_the_verifier_sees_the_request_it_is_judging
    seen = nil
    request = cloudflare_request
    Trackdown.configure do |config|
      config.verify_request_came_through_trusted_cloudflare_path_with { |candidate| seen = candidate }
    end

    Trackdown.locate('203.0.113.9', request: request)

    assert_same request, seen
  end

  def test_an_unavailable_cloudflare_result_still_reports_its_trust
    verify_trusted_cdn_path_with_header
    request = mock_request('HTTP_CF_IPCOUNTRY' => 'XX', 'HTTP_X_ORIGIN_SECRET' => 'shared-secret')

    result = Trackdown::Providers::CloudflareProvider.locate('203.0.113.9', request: request)

    assert_predicate result, :unavailable?
    assert_equal :host_verified, result.source_trust
  end

  def test_maxmind_has_no_request_path_to_trust
    with_maxmind_database do
      result = Trackdown::Providers::MaxmindProvider.locate('203.0.113.9')

      assert_nil result.source_trust
      refute_predicate result, :source_was_verified_by_host?
    end
  end

  # === MaxMind accuracy and database provenance ===

  def test_maxmind_names_itself_and_its_source
    with_maxmind_database do
      result = Trackdown::Providers::MaxmindProvider.locate('203.0.113.9')

      assert_equal :maxmind, result.provider_name
      assert_equal :maxmind_local_database, result.provider_source
    end
  end

  def test_maxmind_reports_the_accuracy_radius_and_its_confidence
    with_maxmind_database do
      result = Trackdown::Providers::MaxmindProvider.locate('203.0.113.9')

      assert_equal 20, result.accuracy_radius_in_kilometers
      assert_equal 20, result.accuracy_radius_km
      assert_equal 67, result.accuracy_radius_confidence_percentage
    end
  end

  def test_maxmind_reports_no_confidence_without_a_radius
    record = full_maxmind_record
    record['location'].delete('accuracy_radius')

    with_maxmind_database(record: record) do
      result = Trackdown::Providers::MaxmindProvider.locate('203.0.113.9')

      assert_nil result.accuracy_radius_in_kilometers
      assert_nil result.accuracy_radius_confidence_percentage
    end
  end

  def test_maxmind_reports_a_zero_kilometre_radius_faithfully
    record = full_maxmind_record
    record['location']['accuracy_radius'] = 0

    with_maxmind_database(record: record) do
      result = Trackdown::Providers::MaxmindProvider.locate('203.0.113.9')

      assert_equal 0, result.accuracy_radius_in_kilometers
      assert_equal 67, result.accuracy_radius_confidence_percentage
    end
  end

  def test_maxmind_reports_which_database_answered
    with_maxmind_database(contents: 'database contents', build_epoch: 1_735_689_600) do
      result = Trackdown::Providers::MaxmindProvider.locate('203.0.113.9')

      assert_equal 1_735_689_600, result.database_build_epoch
      assert_equal Time.utc(2025, 1, 1), result.database_built_at
      assert_equal Digest::SHA256.hexdigest('database contents'), result.database_sha256
    end
  end

  def test_maxmind_digests_once_per_open_database_generation_not_once_per_lookup
    with_maxmind_database do |path|
      first = Trackdown::Providers::MaxmindProvider.locate('203.0.113.9')
      fingerprint = Trackdown::Providers::MaxmindProvider.database_fingerprint
      second = Trackdown::Providers::MaxmindProvider.locate('198.51.100.4')

      assert_same fingerprint, Trackdown::Providers::MaxmindProvider.database_fingerprint
      assert_equal path, fingerprint.path

      # Delete the file after the first digest: a second read would have to fail.
      digest = first.database_sha256
      File.delete(path)

      assert_equal digest, second.database_sha256
    end
  end

  def test_maxmind_does_not_read_the_database_file_unless_the_digest_is_asked_for
    with_maxmind_database do |path|
      result = Trackdown::Providers::MaxmindProvider.locate('203.0.113.9')
      File.delete(path)

      # The lookup itself never touched the file, so everything else still works.
      assert_equal 'US', result.country_code
      assert_equal 1_735_689_600, result.database_build_epoch
      assert_nil result.database_sha256
    end
  end

  def test_maxmind_survives_a_database_without_readable_metadata
    with_maxmind_database(metadata: nil) do
      result = Trackdown::Providers::MaxmindProvider.locate('203.0.113.9')

      assert_nil result.database_build_epoch
      assert_equal 'US', result.country_code
    end
  end

  def test_maxmind_survives_metadata_that_blows_up
    with_maxmind_database(metadata_error: RuntimeError.new('corrupt metadata')) do
      result = Trackdown::Providers::MaxmindProvider.locate('203.0.113.9')

      assert_nil result.database_build_epoch
      assert_equal 'US', result.country_code
    end
  end

  def test_maxmind_notices_a_replaced_database
    with_maxmind_database do |path|
      Trackdown::Providers::MaxmindProvider.reset_database!
      Trackdown::Providers::MaxmindProvider.locate('203.0.113.9')
      File.binwrite(path, 'an entirely different database')

      assert_predicate Trackdown::Providers::MaxmindProvider.database_fingerprint, :changed?
    end
  end

  def test_maxmind_fingerprints_a_second_database_when_the_path_changes
    first_digest = nil

    with_maxmind_database(contents: 'the first database') do
      first_digest = Trackdown::Providers::MaxmindProvider.locate('203.0.113.9').database_sha256
    end

    with_maxmind_database(contents: 'the second database') do
      second = Trackdown::Providers::MaxmindProvider.locate('203.0.113.9')

      assert_equal Digest::SHA256.hexdigest('the first database'), first_digest
      assert_equal Digest::SHA256.hexdigest('the second database'), second.database_sha256
    end
  end

  def test_maxmind_fingerprints_one_database_even_under_concurrent_lookups
    with_maxmind_database do
      results = Array.new(8) { Thread.new { Trackdown::Providers::MaxmindProvider.locate('203.0.113.9') } }.map(&:value)
      digests = results.map(&:database_sha256)

      assert_equal 1, digests.uniq.length
      assert_equal 1, results.map(&:database_build_epoch).uniq.length
      refute_nil digests.first
    end
  end

  def test_each_result_keeps_the_fingerprint_of_the_reader_that_answered
    # MODE_MEMORY readers keep the bytes they opened even after the path changes:
    # https://github.com/maxmind/MaxMind-DB-Reader-ruby/blob/v1.2.0/lib/maxmind/db/memory_reader.rb#L7-L15
    # A real connection pool can therefore briefly contain readers from two
    # database generations. Their provenance must never cross.
    with_maxmind_database_file('old database bytes') do |path|
      old_reader = TestHelpers::MaxmindStubs::FakeReader.new(
        record: full_maxmind_record.merge('country' => { 'iso_code' => 'US', 'names' => { 'en' => 'United States' } }),
        build_epoch: 1
      )
      old_database_reader = TestHelpers::MaxmindStubs.database_reader_for(old_reader)

      File.binwrite(path, 'new database bytes')
      new_reader = TestHelpers::MaxmindStubs::FakeReader.new(
        record: full_maxmind_record.merge('country' => { 'iso_code' => 'GB', 'names' => { 'en' => 'United Kingdom' } }),
        build_epoch: 2
      )
      new_database_reader = TestHelpers::MaxmindStubs.database_reader_for(new_reader)
      pool = TestHelpers::MaxmindStubs::FakeReaderSequencePool.new(
        [old_database_reader, new_database_reader, old_database_reader]
      )
      open_maxmind_pool(pool)

      old_result = Trackdown::Providers::MaxmindProvider.locate('203.0.113.1')
      new_result = Trackdown::Providers::MaxmindProvider.locate('203.0.113.2')
      old_result_again = Trackdown::Providers::MaxmindProvider.locate('203.0.113.3')

      assert_equal ['US', 1], [old_result.country_code, old_result.database_build_epoch]
      assert_equal ['GB', 2], [new_result.country_code, new_result.database_build_epoch]
      assert_equal ['US', 1], [old_result_again.country_code, old_result_again.database_build_epoch]
      assert_nil old_result.database_sha256, 'an old reader must never digest the new file now at its path'
      assert_nil old_result_again.database_sha256
      assert_equal Digest::SHA256.hexdigest('new database bytes'), new_result.database_sha256
    end
  end

  def test_a_result_digest_is_safe_to_read_from_several_threads
    with_maxmind_database do
      result = Trackdown::Providers::MaxmindProvider.locate('203.0.113.9')
      digests = Array.new(8) { Thread.new { result.database_sha256 } }.map(&:value)

      assert_equal 1, digests.uniq.length
      refute_nil digests.first
    end
  end

  def test_updating_the_database_forgets_the_old_one
    with_maxmind_database do
      Trackdown::Providers::MaxmindProvider.locate('203.0.113.9')

      refute_nil Trackdown::Providers::MaxmindProvider.database_fingerprint

      Trackdown::Providers::MaxmindProvider.reset_database!

      assert_nil Trackdown::Providers::MaxmindProvider.database_fingerprint
    end
  end

  def test_forgetting_the_database_lets_go_of_the_open_one
    reader = TestHelpers::MaxmindStubs::FakeReader.new(record: full_maxmind_record)
    open_maxmind_pool(TestHelpers::MaxmindStubs::FakeReaderPool.new(reader))

    Trackdown::Providers::MaxmindProvider.reset_database!

    assert_nil Trackdown::Providers::MaxmindProvider.instance_variable_get(:@reader_pool)
    assert_nil Trackdown::Providers::MaxmindProvider.database_fingerprint
  end

  def test_a_refresh_does_not_break_a_lookup_that_is_already_in_flight
    # The lookup takes its reader, a refresh lands mid-flight, and the lookup
    # still has to finish: swapping the database must never surface as a 500.
    with_maxmind_database_file do
      reader = TestHelpers::MaxmindStubs::FakeReader.new(record: full_maxmind_record, build_epoch: 1)
      reader.define_singleton_method(:get) do |ip|
        Trackdown::Providers::MaxmindProvider.reset_database!
        super(ip)
      end
      open_maxmind_pool(TestHelpers::MaxmindStubs::FakeReaderPool.new(reader))

      result = Trackdown::Providers::MaxmindProvider.locate('203.0.113.9')

      assert_equal 'US', result.country_code
      assert_equal 1, result.database_build_epoch
      assert_equal Digest::SHA256.hexdigest('a pretend GeoLite2-City database'), result.database_sha256
    end
  end

  def test_maxmind_re_fingerprints_when_the_database_underneath_it_is_replaced
    with_maxmind_database_file do |path|
      old_reader = TestHelpers::MaxmindStubs::FakeReader.new(
        record: full_maxmind_record,
        build_epoch: 1_700_000_000
      )
      open_maxmind_pool(TestHelpers::MaxmindStubs::FakeReaderPool.new(old_reader))
      Trackdown::Providers::MaxmindProvider.locate('203.0.113.9')

      # The .mmdb is replaced by another process and a newly opened reader serves it.
      # An existing MODE_MEMORY reader intentionally keeps serving its old bytes:
      # https://github.com/maxmind/MaxMind-DB-Reader-ruby/blob/v1.2.0/lib/maxmind/db/memory_reader.rb#L7-L15
      File.binwrite(path, 'a newer GeoLite2-City database')
      new_reader = TestHelpers::MaxmindStubs::FakeReader.new(
        record: full_maxmind_record,
        build_epoch: 1_800_000_000
      )
      open_maxmind_pool(TestHelpers::MaxmindStubs::FakeReaderPool.new(new_reader))

      result = Trackdown::Providers::MaxmindProvider.locate('203.0.113.9')

      assert_equal 1_800_000_000, result.database_build_epoch,
                   'a result must never be stamped with the previous database\'s build date'
      assert_equal Digest::SHA256.hexdigest('a newer GeoLite2-City database'), result.database_sha256
    end
  end

  def test_maxmind_looks_up_the_address_it_was_given
    with_maxmind_database do |_path, reader|
      Trackdown::Providers::MaxmindProvider.locate('198.51.100.4')

      assert_equal ['198.51.100.4'], reader.requested_ips
    end
  end

  # === Explicit unavailable states ===

  def test_no_provider_available_says_so
    Trackdown.configuration.database_path = '/nonexistent/GeoLite2-City.mmdb'

    result = without_warnings { Trackdown.locate('203.0.113.9') }

    assert_predicate result, :unavailable?
    assert_equal :no_provider_available, result.unavailable_reason
    assert_nil result.provider_name
    assert_nil result.provider_source
    refute_predicate result, :estimated?
  end

  def test_an_address_missing_from_the_database_says_so
    with_maxmind_database(record: nil) do
      result = Trackdown::Providers::MaxmindProvider.locate('203.0.113.9')

      assert_predicate result, :unavailable?
      assert_equal :address_not_found, result.unavailable_reason
    end
  end

  def test_an_address_missing_from_the_database_still_says_which_database_it_looked_in
    with_maxmind_database(record: nil, contents: 'database contents') do
      result = Trackdown::Providers::MaxmindProvider.locate('203.0.113.9')

      assert_equal :maxmind, result.provider_name
      assert_equal :maxmind_local_database, result.provider_source
      assert_equal 1_735_689_600, result.database_build_epoch
      assert_equal Digest::SHA256.hexdigest('database contents'), result.database_sha256
    end
  end

  def test_a_cloudflare_request_without_a_country_says_so
    result = Trackdown::Providers::CloudflareProvider.locate('203.0.113.9', request: mock_request_with_xx_country)

    assert_predicate result, :unavailable?
    assert_equal :provider_returned_unknown_country, result.unavailable_reason
    assert_equal :cloudflare, result.provider_name
  end

  def test_a_cloudflare_request_with_no_country_header_at_all_says_so
    result = Trackdown::Providers::CloudflareProvider.locate('203.0.113.9', request: mock_request_without_cloudflare)

    assert_predicate result, :unavailable?
    assert_equal :provider_returned_unknown_country, result.unavailable_reason
  end

  def test_a_tor_visitor_is_a_country_cloudflare_could_not_determine
    result = Trackdown::Providers::CloudflareProvider.locate('203.0.113.9', request: mock_request_with_tor)

    assert_equal 'T1', result.country_code, 'the code Cloudflare sent is preserved'
    assert_equal '🏳️', result.flag_emoji, 'a pseudo-code must not render a broken regional-indicator glyph'
    assert_predicate result, :unavailable?
    assert_equal :provider_returned_unknown_country, result.unavailable_reason
  end

  def test_a_country_code_we_have_never_heard_of_is_still_an_answer
    # Kosovo's user-assigned "XK" isn't in the countries gem, and a CDN is allowed
    # to know about places our dependencies don't. Only Cloudflare's own XX and T1
    # mean "no country" — an unfamiliar code is a real, available result.
    request = mock_cloudflare_request(country: 'XK', city: 'Pristina',
                                      latitude: '42.6629', longitude: '21.1655')
    result = Trackdown::Providers::CloudflareProvider.locate('203.0.113.9', request: request)

    assert_predicate result, :available?
    assert_nil result.unavailable_reason
    assert_equal 'XK', result.country_code
    assert_equal 'Pristina', result.city
    assert_in_delta 42.6629, result.latitude
  end

  def test_a_cloudfront_request_without_a_usable_country_says_so
    result = Trackdown::Providers::CloudfrontProvider.locate('203.0.113.9',
                                                             request: mock_cloudfront_request(country: 'ZZ'))

    assert_predicate result, :unavailable?
    assert_equal :provider_returned_unknown_country, result.unavailable_reason
    assert_nil result.country_code
    assert_equal 'Unknown', result.country_name
    assert_equal :cloudfront, result.provider_name
  end

  def test_a_database_record_without_a_country_is_incomplete_rather_than_missing
    record = { 'city' => { 'names' => { 'en' => 'Somewhere' } }, 'location' => { 'latitude' => 1.0 } }

    with_maxmind_database(record: record) do
      result = Trackdown::Providers::MaxmindProvider.locate('203.0.113.9')

      assert_predicate result, :unavailable?
      assert_equal :provider_data_incomplete, result.unavailable_reason
      assert_equal 'Somewhere', result.city, 'partial data is still handed back'
      assert_in_delta 1.0, result.latitude
      assert_predicate result, :estimated?, 'partial provider-derived coordinates remain estimates'
    end
  end

  def test_every_unavailable_state_is_distinct
    reasons = []

    Trackdown.configuration.database_path = '/nonexistent/GeoLite2-City.mmdb'
    reasons << without_warnings { Trackdown.locate('203.0.113.9') }.unavailable_reason

    with_maxmind_database(record: nil) do
      reasons << Trackdown::Providers::MaxmindProvider.locate('203.0.113.9').unavailable_reason
    end

    reasons << Trackdown::Providers::CloudflareProvider.locate('203.0.113.9',
                                                               request: mock_request_with_xx_country).unavailable_reason

    with_maxmind_database(record: { 'city' => { 'names' => { 'en' => 'Somewhere' } } }) do
      reasons << Trackdown::Providers::MaxmindProvider.locate('203.0.113.9').unavailable_reason
    end

    assert_equal %i[no_provider_available address_not_found provider_returned_unknown_country provider_data_incomplete],
                 reasons
    assert_equal reasons.uniq, reasons
  end

  # === The provider that actually won is the provider that gets named ===

  def test_auto_names_cloudflare_when_cloudflare_wins
    request = mock_cloudflare_request_with_matching_ip(ip: '203.0.113.9')
    result = Trackdown.locate('203.0.113.9', request: request)

    assert_equal :cloudflare, result.provider_name
    assert_equal :cloudflare_request_headers, result.provider_source
  end

  def test_auto_names_cloudfront_when_cloudfront_wins
    request = mock_cloudfront_request_with_matching_ip(ip: '203.0.113.9')
    result = Trackdown.locate('203.0.113.9', request: request)

    assert_equal :cloudfront, result.provider_name
    assert_equal :cloudfront_request_headers, result.provider_source
  end

  def test_auto_names_cloudflare_for_an_ipv6_visitor
    request = mock_cloudflare_request_with_matching_ip(ip: '2001:db8::1')
    result = Trackdown.locate('2001:db8::1', request: request)

    assert_equal :cloudflare, result.provider_name
  end

  def test_auto_names_cloudfront_for_an_ipv6_visitor
    request = mock_cloudfront_request_with_matching_ip(ip: '2001:db8::1')
    result = Trackdown.locate('2001:db8::1', request: request)

    assert_equal :cloudfront, result.provider_name
  end

  def test_auto_names_cloudflare_for_an_ipv4_mapped_ipv6_visitor
    request = mock_cloudflare_request_with_matching_ip(ip: '::ffff:203.0.113.9')
    result = Trackdown.locate('203.0.113.9', request: request)

    assert_equal :cloudflare, result.provider_name
  end

  def test_auto_names_cloudfront_for_an_ipv4_mapped_ipv6_visitor
    request = mock_cloudfront_request_with_matching_ip(ip: '::ffff:203.0.113.9')
    result = Trackdown.locate('203.0.113.9', request: request)

    assert_equal :cloudfront, result.provider_name
  end

  def test_auto_names_maxmind_after_a_cloudflare_ip_mismatch
    request = mock_cloudflare_request_with_proxy(proxy_ip: '198.51.100.7')

    with_maxmind_database do
      result = without_warnings { Trackdown.locate('203.0.113.9', request: request) }

      assert_equal :maxmind, result.provider_name
      assert_equal :maxmind_local_database, result.provider_source
      assert_equal 1_735_689_600, result.database_build_epoch
    end
  end

  def test_auto_names_maxmind_after_a_cloudfront_ip_mismatch
    request = mock_cloudfront_request_with_proxy(proxy_ip: '198.51.100.7')

    with_maxmind_database do
      result = without_warnings { Trackdown.locate('203.0.113.9', request: request) }

      assert_equal :maxmind, result.provider_name
    end
  end

  def test_auto_names_maxmind_when_both_cdns_look_valid
    request = mock_cloudflare_request_with_matching_ip(ip: '203.0.113.9')
    request.env['HTTP_CLOUDFRONT_VIEWER_COUNTRY'] = 'GB'
    request.env['HTTP_CLOUDFRONT_VIEWER_ADDRESS'] = '203.0.113.9:46532'

    with_maxmind_database do
      result = without_warnings { Trackdown.locate('203.0.113.9', request: request) }

      assert_equal :maxmind, result.provider_name
    end
  end

  def test_auto_reports_no_provider_after_a_mismatch_with_no_database
    request = mock_cloudflare_request_with_proxy(proxy_ip: '198.51.100.7')
    Trackdown.configuration.database_path = '/nonexistent/GeoLite2-City.mmdb'

    result = without_warnings { Trackdown.locate('203.0.113.9', request: request) }

    assert_equal :no_provider_available, result.unavailable_reason
    assert_nil result.provider_name
  end

  def test_auto_names_maxmind_when_there_is_no_request_at_all
    with_maxmind_database do
      result = Trackdown.locate('203.0.113.9')

      assert_equal :maxmind, result.provider_name
    end
  end

  def test_auto_names_cloudflare_when_the_header_carries_the_mapped_form_of_the_address
    request = mock_cloudflare_request_with_matching_ip(ip: '203.0.113.9')
    result = Trackdown.locate('::ffff:203.0.113.9', request: request)

    assert_equal :cloudflare, result.provider_name
  end

  def test_auto_names_cloudfront_when_the_header_carries_the_mapped_form_of_the_address
    request = mock_cloudfront_request_with_matching_ip(ip: '203.0.113.9')
    result = Trackdown.locate('::ffff:203.0.113.9', request: request)

    assert_equal :cloudfront, result.provider_name
  end

  def test_an_explicitly_configured_cloudflare_provider_names_itself
    Trackdown.configuration.provider = :cloudflare
    result = Trackdown.locate('203.0.113.9', request: cloudflare_request)

    assert_equal :cloudflare, result.provider_name
    assert_equal :cloudflare_request_headers, result.provider_source
  end

  def test_an_explicitly_configured_cloudfront_provider_names_itself
    Trackdown.configuration.provider = :cloudfront
    result = Trackdown.locate('203.0.113.9', request: mock_cloudfront_request_with_all_headers)

    assert_equal :cloudfront, result.provider_name
    assert_equal :cloudfront_request_headers, result.provider_source
  end

  def test_an_explicitly_configured_maxmind_provider_names_itself
    with_maxmind_database do
      Trackdown.configuration.provider = :maxmind
      result = Trackdown.locate('203.0.113.9', request: cloudflare_request)

      assert_equal :maxmind, result.provider_name
      assert_equal :maxmind_local_database, result.provider_source
      assert_nil result.source_trust, 'a local database has no request path to verify'
    end
  end

  # === Minimized serialization, end to end ===

  def test_a_caller_can_serialize_only_the_fields_it_wants_to_keep
    with_maxmind_database do
      result = Trackdown::Providers::MaxmindProvider.locate('203.0.113.9')

      hash = result.to_h(
        only: %i[country_code region_code city latitude longitude
                 accuracy_radius_in_kilometers provider_name provider_source],
        include_country_info: false
      )

      assert_equal %i[country_code region_code city latitude longitude
                      accuracy_radius_in_kilometers provider_name provider_source], hash.keys
      assert_equal 'US', hash[:country_code]
      assert_equal 'CA', hash[:region_code]
      assert_equal 'San Francisco', hash[:city]
      assert_equal 20, hash[:accuracy_radius_in_kilometers]
      assert_equal :maxmind, hash[:provider_name]
      assert_equal :maxmind_local_database, hash[:provider_source]
      refute_includes hash.keys, :country_info
    end
  end

  def test_the_full_hash_still_carries_everything_including_provenance
    result = Trackdown.locate('203.0.113.9', request: cloudflare_request)
    hash = result.to_h(include_provenance: true)

    assert_equal 'US', hash[:country_code]
    assert_equal :cloudflare, hash[:provider_name]
    assert_equal :cloudflare_request_headers, hash[:provider_source]
    assert_equal :unverified, hash[:source_trust]
    assert hash[:available]
    assert_equal 'US', hash[:country_info]['alpha2']
  end
end
