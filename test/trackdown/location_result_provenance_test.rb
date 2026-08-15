# frozen_string_literal: true

require "test_helper"

# Everything a result says about *how* it knows what it knows.
class LocationResultProvenanceTest < Minitest::Test
  def build(country_code = 'US', **provenance)
    Trackdown::LocationResult.new(country_code, 'United States', 'San Francisco', '🇺🇸', **provenance)
  end

  # === Provider provenance ===

  def test_provider_name_and_source_are_recorded
    result = build('US', provider_name: :cloudflare, provider_source: :cloudflare_request_headers)

    assert_equal :cloudflare, result.provider_name
    assert_equal :cloudflare_request_headers, result.provider_source
  end

  def test_provider_is_an_alias_for_provider_name
    result = build('US', provider_name: :maxmind)

    assert_equal :maxmind, result.provider
  end

  def test_provider_provenance_defaults_to_nil
    result = build

    assert_nil result.provider_name
    assert_nil result.provider_source
  end

  def test_resolved_at_defaults_to_now_in_utc
    before = Time.now.utc
    result = build
    after = Time.now.utc

    assert_kind_of Time, result.resolved_at
    assert_equal 'UTC', result.resolved_at.zone
    assert_operator result.resolved_at, :>=, before
    assert_operator result.resolved_at, :<=, after
  end

  def test_resolved_at_can_be_supplied
    moment = Time.utc(2026, 1, 2, 3, 4, 5)
    result = build('US', resolved_at: moment)

    assert_equal moment, result.resolved_at
  end

  # === Estimated ===

  def test_a_resolved_location_is_always_an_estimate
    assert_predicate build, :estimated?
  end

  def test_an_unresolved_location_estimates_nothing
    refute_predicate Trackdown::LocationResult.unavailable(:address_not_found), :estimated?
  end

  # === Accuracy ===

  def test_accuracy_radius_is_recorded_with_its_confidence
    result = build('US', accuracy_radius_in_kilometers: 20, accuracy_radius_confidence_percentage: 67)

    assert_equal 20, result.accuracy_radius_in_kilometers
    assert_equal 67, result.accuracy_radius_confidence_percentage
  end

  def test_accuracy_radius_km_is_an_alias
    result = build('US', accuracy_radius_in_kilometers: 5)

    assert_equal 5, result.accuracy_radius_km
  end

  def test_accuracy_defaults_to_nil_rather_than_an_invented_value
    result = build

    assert_nil result.accuracy_radius_in_kilometers
    assert_nil result.accuracy_radius_confidence_percentage
  end

  # === Database provenance ===

  def test_database_build_epoch_and_digest_are_recorded
    result = build('US', database_build_epoch: 1_735_689_600, database_sha256: 'abc123')

    assert_equal 1_735_689_600, result.database_build_epoch
    assert_equal 'abc123', result.database_sha256
  end

  def test_database_built_at_reads_the_build_epoch_as_a_utc_time
    result = build('US', database_build_epoch: 1_735_689_600)

    assert_equal Time.utc(2025, 1, 1), result.database_built_at
    assert_equal 'UTC', result.database_built_at.zone
  end

  def test_database_built_at_is_nil_without_a_build_epoch
    assert_nil build.database_built_at
  end

  def test_database_built_at_refuses_to_guess_at_a_nonsense_build_epoch
    assert_nil build('US', database_build_epoch: 'the day before yesterday').database_built_at
  end

  def test_a_digest_that_cannot_be_computed_stays_nil
    attempts = 0
    result = build('US', database_sha256: -> { attempts += 1; nil })

    assert_nil result.database_sha256
    assert_nil result.database_sha256
    assert_equal 1, attempts, 'a digest we could not compute should not be retried on every read'
  end

  def test_database_digest_is_only_computed_when_someone_asks_for_it
    computations = 0
    result = build('US', database_sha256: -> { computations += 1; 'digest' })

    assert_equal 0, computations

    assert_equal 'digest', result.database_sha256
    assert_equal 'digest', result.database_sha256
    assert_equal 1, computations, 'the digest should be computed once and then reused'
  end

  def test_database_defaults_to_nil
    result = build

    assert_nil result.database_build_epoch
    assert_nil result.database_sha256
  end

  # === Availability ===

  def test_a_result_with_a_country_is_available
    result = build

    assert_predicate result, :available?
    refute_predicate result, :unavailable?
    assert_nil result.unavailable_reason
  end

  def test_a_result_without_a_country_is_unavailable
    result = Trackdown::LocationResult.new(nil, 'Unknown', 'Unknown', '🏳️')

    refute_predicate result, :available?
    assert_predicate result, :unavailable?
    assert_equal :provider_data_incomplete, result.unavailable_reason
  end

  def test_a_blank_country_code_is_unavailable_too
    result = Trackdown::LocationResult.new('', 'Unknown', 'Unknown', '🏳️')

    assert_predicate result, :unavailable?
    assert_equal :provider_data_incomplete, result.unavailable_reason
  end

  def test_an_explicit_reason_wins_over_the_default
    result = Trackdown::LocationResult.new(nil, 'Unknown', 'Unknown', '🏳️',
                                           unavailable_reason: :address_not_found)

    assert_equal :address_not_found, result.unavailable_reason
  end

  def test_a_reason_can_accompany_a_country_code_the_provider_could_not_resolve
    # Cloudflare's "T1" names the Tor network, not a country.
    result = Trackdown::LocationResult.new('T1', 'Unknown', 'Unknown', '🏳️',
                                           unavailable_reason: :provider_returned_unknown_country)

    assert_equal 'T1', result.country_code
    assert_predicate result, :unavailable?
    assert_equal :provider_returned_unknown_country, result.unavailable_reason
  end

  def test_every_documented_unavailable_reason_is_accepted
    Trackdown::LocationResult::UNAVAILABLE_REASONS.each do |reason|
      assert_equal reason, Trackdown::LocationResult.unavailable(reason).unavailable_reason
    end
  end

  def test_the_documented_unavailable_reasons_are_exactly_these_four
    assert_equal %i[no_provider_available address_not_found provider_returned_unknown_country provider_data_incomplete],
                 Trackdown::LocationResult::UNAVAILABLE_REASONS
  end

  def test_an_unknown_unavailable_reason_is_rejected
    error = assert_raises(ArgumentError) { Trackdown::LocationResult.unavailable(:made_up) }

    assert_match(/Unknown unavailable reason: :made_up/, error.message)
    assert_match(/no_provider_available/, error.message)
  end

  # === The unavailable constructor ===

  def test_unavailable_builds_the_familiar_unknown_shape
    result = Trackdown::LocationResult.unavailable(:no_provider_available)

    assert_nil result.country_code
    assert_equal 'Unknown', result.country_name
    assert_equal 'Unknown', result.city
    assert_equal '🏳️', result.flag_emoji
    assert_nil result.country_info
  end

  def test_unavailable_carries_provenance_through
    result = Trackdown::LocationResult.unavailable(
      :address_not_found,
      provider_name: :maxmind,
      provider_source: :maxmind_local_database,
      database_build_epoch: 1_735_689_600
    )

    assert_equal :maxmind, result.provider_name
    assert_equal :maxmind_local_database, result.provider_source
    assert_equal 1_735_689_600, result.database_build_epoch
    assert_equal :address_not_found, result.unavailable_reason
  end

  # === Source trust ===

  def test_source_trust_defaults_to_nil_when_no_request_was_involved
    result = build

    assert_nil result.source_trust
    refute_predicate result, :source_was_verified_by_host?
  end

  def test_unverified_source_trust
    result = build('US', source_trust: :unverified)

    assert_equal :unverified, result.source_trust
    refute_predicate result, :source_was_verified_by_host?
    refute_predicate result, :host_verified?
  end

  def test_host_verified_source_trust
    result = build('US', source_trust: :host_verified)

    assert_equal :host_verified, result.source_trust
    assert_predicate result, :source_was_verified_by_host?
    assert_predicate result, :host_verified?
  end

  def test_the_documented_source_trust_states_are_exactly_these_two
    assert_equal %i[unverified host_verified], Trackdown::LocationResult::SOURCE_TRUSTS
  end

  def test_an_unknown_source_trust_is_rejected
    error = assert_raises(ArgumentError) { build('US', source_trust: :probably_fine) }

    assert_match(/Unknown source trust: :probably_fine/, error.message)
    assert_match(/unverified, host_verified/, error.message)
  end

  # === Serialization ===

  def test_to_h_includes_every_provenance_field
    result = build(
      'US',
      provider_name: :maxmind,
      provider_source: :maxmind_local_database,
      source_trust: :unverified,
      accuracy_radius_in_kilometers: 20,
      accuracy_radius_confidence_percentage: 67,
      database_build_epoch: 1_735_689_600,
      database_sha256: 'abc123'
    )
    hash = result.to_h

    assert_equal :maxmind, hash[:provider_name]
    assert_equal :maxmind_local_database, hash[:provider_source]
    assert_equal :unverified, hash[:source_trust]
    assert_equal 20, hash[:accuracy_radius_in_kilometers]
    assert_equal 67, hash[:accuracy_radius_confidence_percentage]
    assert_equal 1_735_689_600, hash[:database_build_epoch]
    assert_equal Time.utc(2025, 1, 1), hash[:database_built_at]
    assert_equal result.resolved_at, hash[:resolved_at]
    assert hash[:available]
    assert hash[:estimated]
    assert_nil hash[:unavailable_reason]
  end

  def test_to_h_reports_unavailability
    hash = Trackdown::LocationResult.unavailable(:no_provider_available).to_h

    refute hash[:available]
    refute hash[:estimated]
    assert_equal :no_provider_available, hash[:unavailable_reason]
  end

  def test_to_h_emits_every_documented_field_by_default
    assert_equal Trackdown::LocationResult::DEFAULT_FIELDS, build.to_h.keys
  end

  def test_the_digest_is_the_only_field_you_have_to_ask_for
    assert_equal %i[database_sha256],
                 Trackdown::LocationResult::FIELDS - Trackdown::LocationResult::DEFAULT_FIELDS
  end

  def test_to_h_does_not_compute_the_digest_unless_you_name_it
    computations = 0
    result = build('US', database_sha256: -> { computations += 1; 'digest' })

    refute_includes result.to_h.keys, :database_sha256
    assert_equal 0, computations, 'serializing a result must never cost a database read'

    assert_equal 'digest', result.to_h(only: %i[database_sha256])[:database_sha256]
    assert_equal 1, computations
  end

  def test_to_h_only_returns_exactly_the_requested_fields
    result = build('US', provider_name: :cloudflare, accuracy_radius_in_kilometers: 20)
    hash = result.to_h(only: %i[country_code city provider_name accuracy_radius_in_kilometers])

    assert_equal %i[country_code city provider_name accuracy_radius_in_kilometers], hash.keys
    assert_equal 'US', hash[:country_code]
    assert_equal 'San Francisco', hash[:city]
    assert_equal :cloudflare, hash[:provider_name]
    assert_equal 20, hash[:accuracy_radius_in_kilometers]
  end

  def test_to_h_only_never_includes_country_info_unless_you_ask
    refute_includes build.to_h(only: %i[country_code]).keys, :country_info
  end

  def test_to_h_only_can_include_country_info_when_asked
    hash = build.to_h(only: %i[country_code country_info])

    assert_equal %i[country_code country_info], hash.keys
    assert_equal 'US', hash[:country_info]['alpha2']
  end

  def test_to_h_only_preserves_the_order_you_asked_for
    hash = build.to_h(only: %i[city country_code flag_emoji])

    assert_equal %i[city country_code flag_emoji], hash.keys
  end

  def test_to_h_only_accepts_a_single_field
    assert_equal({ country_code: 'US' }, build.to_h(only: :country_code))
  end

  def test_to_h_only_accepts_strings
    assert_equal({ country_code: 'US' }, build.to_h(only: %w[country_code]))
  end

  def test_to_h_only_deduplicates
    assert_equal %i[city], build.to_h(only: %i[city city]).keys
  end

  def test_to_h_only_with_an_empty_list_returns_an_empty_hash
    assert_empty build.to_h(only: [])
  end

  def test_to_h_only_computes_the_predicate_fields
    hash = build.to_h(only: %i[available estimated])

    assert hash[:available]
    assert hash[:estimated]
  end

  def test_to_h_rejects_a_field_that_does_not_exist
    error = assert_raises(ArgumentError) { build.to_h(only: %i[country_code contry_code]) }

    assert_match(/Unknown field for LocationResult#to_h: :contry_code/, error.message)
    assert_match(/Available fields: country_code/, error.message)
  end

  def test_to_h_rejects_something_that_is_not_a_field_name_at_all
    error = assert_raises(ArgumentError) { build.to_h(only: [123]) }

    assert_match(/Unknown field for LocationResult#to_h: 123/, error.message)
  end

  def test_to_h_names_every_field_it_does_not_recognize
    error = assert_raises(ArgumentError) { build.to_h(only: %i[nope nah]) }

    assert_match(/Unknown fields for LocationResult#to_h: :nope, :nah/, error.message)
  end

  def test_to_h_can_leave_out_the_large_country_info_payload
    hash = build.to_h(include_country_info: false)

    refute_includes hash.keys, :country_info
    assert_equal 'US', hash[:country_code]
    assert_equal Trackdown::LocationResult::DEFAULT_FIELDS - %i[country_info], hash.keys
  end

  def test_only_says_exactly_what_you_get_even_about_country_info
    hash = build.to_h(only: %i[country_code country_info], include_country_info: false)

    assert_equal %i[country_code country_info], hash.keys,
                 'a field you named explicitly must never be dropped'
  end

  def test_to_h_still_includes_country_info_by_default
    assert_equal 'US', build.to_h[:country_info]['alpha2']
  end

  def test_the_issue_example_serialization
    result = build(
      'US',
      region_code: 'CA',
      latitude: 37.7749,
      longitude: -122.4194,
      accuracy_radius_in_kilometers: 20,
      provider_name: :maxmind,
      provider_source: :maxmind_local_database
    )

    hash = result.to_h(
      only: %i[country_code region_code city latitude longitude
               accuracy_radius_in_kilometers provider_name provider_source],
      include_country_info: false
    )

    assert_equal %i[country_code region_code city latitude longitude
                    accuracy_radius_in_kilometers provider_name provider_source], hash.keys
    refute_includes hash.keys, :country_info
  end

  def test_to_h_resolves_a_lazy_digest_when_you_name_it
    result = build('US', database_sha256: -> { 'lazily-computed' })

    assert_equal 'lazily-computed', result.to_h(only: %i[database_sha256])[:database_sha256]
  end

  def test_unavailable_insists_on_a_reason
    error = assert_raises(ArgumentError) { Trackdown::LocationResult.unavailable(nil) }

    assert_match(/has to say why/, error.message)
  end

  # === Backwards compatibility ===

  def test_the_original_positional_constructor_still_works
    result = Trackdown::LocationResult.new('GB', 'United Kingdom', 'London', '🇬🇧')

    assert_equal 'GB', result.country_code
    assert_equal 'United Kingdom', result.country
    assert_equal '🇬🇧', result.emoji
    assert_predicate result, :available?
  end

  def test_unknown_display_strings_are_preserved_for_existing_callers
    result = Trackdown::LocationResult.unavailable(:no_provider_available)

    assert_equal Trackdown::LocationResult::UNKNOWN, result.country_name
    assert_equal Trackdown::LocationResult::UNKNOWN, result.city
    assert_equal 'Unknown', Trackdown::LocationResult::UNKNOWN
  end
end
