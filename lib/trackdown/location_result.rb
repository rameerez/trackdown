# frozen_string_literal: true

require 'countries'

module Trackdown
  # Where an IP address probably is — and an honest account of how we know.
  #
  # Every result carries its own provenance: which provider answered, from which
  # source, when it answered, how precise that provider says the answer is, and
  # whether the host vouched for the path the request arrived through.
  #
  # Nothing here is guessed. Every field is either what the provider said or
  # something derived from it by a documented rule — never a plausible-looking
  # placeholder. A field the answering provider cannot supply is `nil`, so a
  # caller can always tell "the provider said no" apart from "it never said".
  #
  # GeoIP is an estimate. It never proves that a person or a device was in a
  # place. MaxMind documents those limits exactly:
  # https://support.maxmind.com/knowledge-base/articles/maxmind-geolocation-accuracy
  class LocationResult
    # What providers have always returned for a value they don't have. Kept for
    # backwards compatibility — new code should ask #available? and read the
    # nil-able fields instead of parsing display strings.
    UNKNOWN = 'Unknown'
    UNKNOWN_FLAG = '🏳️'

    # Why a lookup came back with no location. Stable and machine-readable:
    # these symbols are part of the public API and are never translated.
    UNAVAILABLE_REASONS = %i[
      no_provider_available
      address_not_found
      provider_returned_unknown_country
      provider_data_incomplete
    ].freeze

    # How much the host vouches for the source of a request-backed result.
    # :host_verified only ever comes from the host's own verifier — see
    # Trackdown::Configuration#verify_request_came_through_trusted_cdn_path_with.
    SOURCE_TRUSTS = %i[unverified host_verified].freeze

    # Where the IP is.
    LOCATION_FIELDS = %i[
      country_code country_name city flag_emoji
      region region_code continent timezone
      latitude longitude postal_code metro_code
    ].freeze

    # How we know, and how sure we are.
    PROVENANCE_FIELDS = %i[
      provider_name provider_source source_trust resolved_at
      available estimated unavailable_reason
      accuracy_radius_in_kilometers accuracy_radius_confidence_percentage
      database_build_epoch database_built_at database_sha256
    ].freeze

    # Every field #to_h can emit, in the order it emits them.
    FIELDS = (LOCATION_FIELDS + PROVENANCE_FIELDS + %i[country_info]).freeze

    # What #to_h emits when you don't ask for anything in particular.
    #
    # The digest is the one field that costs real work — a full read of the
    # database file — so serializing "everything" deliberately stops short of it.
    # Name it in `only:` when you want it, and never pay for it when you don't.
    DEFAULT_FIELDS = (FIELDS - %i[database_sha256]).freeze

    attr_reader :country_code, :country_name, :city, :flag_emoji,
                :region, :region_code, :continent, :timezone, :latitude, :longitude,
                :postal_code, :metro_code,
                :provider_name, :provider_source, :source_trust, :resolved_at,
                :unavailable_reason,
                :accuracy_radius_in_kilometers, :accuracy_radius_confidence_percentage,
                :database_build_epoch

    # Every keyword is optional, so a provider only supplies what it actually knows.
    #
    # @param database_sha256 [String, #call, nil] the digest itself, or something
    #   that returns it, so an expensive digest is computed only if someone asks.
    #   Concurrent readers may each call it, so a callable should memoize its own
    #   work — Trackdown's does.
    def initialize(country_code, country_name, city, flag_emoji,
                   region: nil, region_code: nil, continent: nil,
                   timezone: nil, latitude: nil, longitude: nil,
                   postal_code: nil, metro_code: nil,
                   provider_name: nil, provider_source: nil, source_trust: nil,
                   resolved_at: nil, unavailable_reason: nil,
                   accuracy_radius_in_kilometers: nil,
                   accuracy_radius_confidence_percentage: nil,
                   database_build_epoch: nil, database_sha256: nil)
      @country_code = country_code
      @country_name = country_name
      @city = city
      @flag_emoji = flag_emoji
      @region = region
      @region_code = region_code
      @continent = continent
      @timezone = timezone
      @latitude = latitude
      @longitude = longitude
      @postal_code = postal_code
      @metro_code = metro_code

      @provider_name = provider_name
      @provider_source = provider_source
      @source_trust = validate!(source_trust, SOURCE_TRUSTS, 'source trust')
      @resolved_at = resolved_at || Time.now.utc
      @unavailable_reason = validate!(unavailable_reason, UNAVAILABLE_REASONS, 'unavailable reason') ||
                            (:provider_data_incomplete if blank?(country_code))
      @accuracy_radius_in_kilometers = accuracy_radius_in_kilometers
      @accuracy_radius_confidence_percentage = accuracy_radius_confidence_percentage
      @database_build_epoch = database_build_epoch
      @database_sha256 = database_sha256
    end

    # A lookup that resolved nothing, and says why.
    #
    #   LocationResult.unavailable(:address_not_found, provider_name: :maxmind)
    def self.unavailable(reason, **provenance)
      if reason.nil?
        raise ArgumentError, "An unavailable result has to say why. Must be one of: #{UNAVAILABLE_REASONS.join(', ')}"
      end

      new(nil, UNKNOWN, UNKNOWN, UNKNOWN_FLAG, unavailable_reason: reason, **provenance)
    end

    alias_method :country, :country_name
    alias_method :emoji, :flag_emoji
    alias_method :emoji_flag, :flag_emoji
    alias_method :country_flag, :flag_emoji
    alias_method :provider, :provider_name
    alias_method :accuracy_radius_km, :accuracy_radius_in_kilometers

    # Did we actually resolve a location?
    def available?
      @unavailable_reason.nil?
    end

    def unavailable?
      !available?
    end

    # Always true for a resolved location: GeoIP infers where an address is
    # likely to be, and never proves where anyone was. A lookup that resolved
    # nothing estimated nothing.
    def estimated?
      available?
    end

    # True only when the host's own verifier vouched for this request's path.
    # Header presence alone never gets you here.
    def source_was_verified_by_host?
      @source_trust == :host_verified
    end
    alias_method :host_verified?, :source_was_verified_by_host?

    # The MaxMind database digest, computed the first time it's asked for.
    def database_sha256
      @database_sha256 = @database_sha256.call if @database_sha256.respond_to?(:call)
      @database_sha256
    end

    # When the database that answered was built.
    def database_built_at
      Time.at(@database_build_epoch).utc if @database_build_epoch.is_a?(Numeric)
    end

    def country_info
      return nil unless country_code

      ISO3166::Country.new(country_code)
    end

    # The whole result as a hash, or exactly the fields you name.
    #
    #   result.to_h
    #   result.to_h(only: %i[country_code city latitude longitude provider_name])
    #   result.to_h(include_country_info: false)
    #
    # @param only [Array<Symbol>, Symbol, nil] the exact fields to serialize, in
    #   the order you name them. What you name is what you get: naming a field
    #   that doesn't exist raises, and nothing you name is ever dropped, so a typo
    #   can't silently cost you a column in a record you're keeping. The full list
    #   of names is FIELDS.
    # @param include_country_info [Boolean] the derived `countries` gem payload is
    #   large; pass false to leave it out of the default shape. Ignored when you
    #   pass `only:`, which already says exactly what you want.
    def to_h(only: nil, include_country_info: true)
      fields = if only
                 requested_fields(only)
               elsif include_country_info
                 DEFAULT_FIELDS
               else
                 DEFAULT_FIELDS - %i[country_info]
               end

      fields.to_h { |field| [field, value_of(field)] }
    end

    private

    def value_of(field)
      case field
      when :available then available?
      when :estimated then estimated?
      when :country_info then country_info&.data || {}
      else public_send(field)
      end
    end

    def requested_fields(only)
      fields = Array(only).map { |field| field.respond_to?(:to_sym) ? field.to_sym : field }
      unknown = fields - FIELDS

      unless unknown.empty?
        raise ArgumentError, "Unknown #{unknown.one? ? 'field' : 'fields'} for LocationResult#to_h: " \
                             "#{unknown.map(&:inspect).join(', ')}. Available fields: #{FIELDS.join(', ')}"
      end

      fields.uniq
    end

    def validate!(value, allowed, description)
      return nil if value.nil?
      return value if allowed.include?(value)

      raise ArgumentError, "Unknown #{description}: #{value.inspect}. Must be one of: #{allowed.join(', ')}"
    end

    def blank?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end
  end
end
