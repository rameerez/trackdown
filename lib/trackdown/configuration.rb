# frozen_string_literal: true

# Conditionally require MaxMind constants if available
begin
  require 'maxmind/db'
  MAXMIND_AVAILABLE = true
rescue LoadError
  MAXMIND_AVAILABLE = false
end

module Trackdown
  class Configuration
    attr_reader :provider, :trusted_cdn_path_verifier
    attr_accessor :maxmind_license_key, :maxmind_account_id, :database_path,
                  :timeout, :pool_size, :pool_timeout, :memory_mode, :reject_private_ips

    # Available provider types:
    # :auto - Use one IP-corroborated CDN provider, otherwise fall back to MaxMind (recommended)
    # :cloudflare - Only use Cloudflare headers
    # :cloudfront - Only use Amazon CloudFront headers
    # :maxmind - Only use MaxMind database
    VALID_PROVIDERS = [:auto, :cloudflare, :cloudfront, :maxmind].freeze

    def initialize
      @provider = :auto # Safe default: use one verified edge candidate, otherwise MaxMind
      @maxmind_license_key = nil
      @maxmind_account_id = nil
      @database_path = defined?(Rails) ? Rails.root.join('db', 'GeoLite2-City.mmdb').to_s : 'db/GeoLite2-City.mmdb'
      @timeout = 3 # seconds
      @pool_size = 5
      @pool_timeout = 3 # seconds
      @memory_mode = MAXMIND_AVAILABLE ? MaxMind::DB::MODE_MEMORY : nil
      @reject_private_ips = true
      @trusted_cdn_path_verifier = nil
      @warned_verifier_raised = false
    end

    def provider=(value)
      unless VALID_PROVIDERS.include?(value)
        raise ArgumentError, "Invalid provider: #{value}. Must be one of: #{VALID_PROVIDERS.join(', ')}"
      end
      @provider = value
    end

    def reject_private_ips?
      @reject_private_ips
    end

    # Tell Trackdown how *you* know a request really came through your CDN, so a
    # result can say `source_trust: :host_verified` instead of `:unverified`:
    #
    #   config.verify_request_came_through_trusted_cdn_path_with do |request|
    #     request.env['HTTP_X_ORIGIN_SECRET'] == Rails.application.credentials.origin_secret
    #   end
    #
    # Trackdown will never infer this for you. CDN geolocation headers can be set
    # by anyone who can reach an unprotected origin directly, so their presence
    # proves nothing. Only your own origin protection does — Authenticated Origin
    # Pulls, an origin-only shared secret, an allowlisted edge IP range:
    # https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-overview.html
    #
    # Trackdown reports this trust state; it does not act on it. Deciding what an
    # unverified location may be used for is your application's call.
    def verify_request_came_through_trusted_cdn_path_with(verifier = nil, &block)
      verifier ||= block

      if verifier.nil?
        raise ArgumentError, 'verify_request_came_through_trusted_cdn_path_with needs a block or a callable ' \
                             'saying how you know a request came through your CDN. ' \
                             'To stop verifying, set config.trusted_cdn_path_verifier = nil.'
      end

      self.trusted_cdn_path_verifier = verifier
    end

    # The same contract, under the name the original proposal used.
    alias_method :verify_request_came_through_trusted_cloudflare_path_with,
                 :verify_request_came_through_trusted_cdn_path_with

    def trusted_cdn_path_verifier=(verifier)
      unless verifier.nil? || verifier.respond_to?(:call)
        raise ArgumentError, "The trusted CDN path verifier must respond to #call (a block, proc, lambda, " \
                             "or any object with a #call method), got: #{verifier.inspect}"
      end

      @warned_verifier_raised = false
      @trusted_cdn_path_verifier = verifier
    end

    # Did the host vouch for this request? Asked fresh every time, never cached,
    # and a verifier that blows up means "no" — a geolocation lookup must not be
    # able to take an application down.
    def request_came_through_trusted_cdn_path?(request)
      return false unless request && @trusted_cdn_path_verifier

      !!@trusted_cdn_path_verifier.call(request)
    rescue StandardError => e
      warn_verifier_raised(e)
      false
    end

    private

    def warn_verifier_raised(error)
      return if @warned_verifier_raised

      @warned_verifier_raised = true
      message = "[Trackdown] Your trusted CDN path verifier raised #{error.class}: #{error.message}. " \
                'Treating the request source as :unverified.'

      defined?(Rails) ? Rails.logger.error(message) : warn(message)
    end
  end
end
