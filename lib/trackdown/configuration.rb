# frozen_string_literal: true

# Conditionally require MaxMind constants if available
begin
  require 'maxmind/db'
  MAXMIND_AVAILABLE = true
rescue LoadError
  MAXMIND_AVAILABLE = false
end

module Trackdown
  # Runtime choices for providers, MaxMind, and provider-specific source trust.
  class Configuration
    attr_reader :provider
    attr_accessor :maxmind_license_key, :maxmind_account_id, :database_path,
                  :timeout, :pool_size, :pool_timeout, :memory_mode, :reject_private_ips

    # Available provider types:
    # :auto - Use one IP-corroborated CDN provider, otherwise fall back to MaxMind (recommended)
    # :cloudflare - Only use Cloudflare headers
    # :cloudfront - Only use Amazon CloudFront headers
    # :maxmind - Only use MaxMind database
    VALID_PROVIDERS = %i[auto cloudflare cloudfront maxmind].freeze
    TRUSTED_CDN_PROVIDERS = %i[cloudflare cloudfront].freeze

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
      @trusted_cdn_path_verifiers = {}
      @warned_verifier_raised = {}
      @verifier_mutex = Mutex.new
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

    # Tell Trackdown how *you* know a request really came through Cloudflare, so
    # only Cloudflare results can say `source_trust: :host_verified`:
    #
    #   expected = Rails.application.credentials.cloudflare_origin_secret.to_s
    #   raise 'Missing Cloudflare origin secret' if expected.empty?
    #
    #   config.verify_request_came_through_trusted_cloudflare_path_with do |request|
    #     supplied = request.env['HTTP_X_ORIGIN_SECRET'].to_s
    #     !supplied.empty? && ActiveSupport::SecurityUtils.secure_compare(supplied, expected)
    #   end
    #
    # The non-empty checks are essential: secure_compare('', '') is true. Rails:
    # https://api.rubyonrails.org/classes/ActiveSupport/SecurityUtils.html#method-c-secure_compare
    #
    # Trackdown never infers trust from headers. Anyone who can reach an
    # unprotected origin can set them. Verify each CDN independently so a trusted
    # CloudFront path can never vouch for forwarded, viewer-supplied CF-* headers:
    # https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/
    # https://developers.cloudflare.com/fundamentals/concepts/cloudflare-ip-addresses/#block-other-ip-addresses-recommended
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/add-origin-custom-headers.html
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-overview.html
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-origin-request-policies.html#managed-origin-request-policy-all-viewer-and-cloudfront
    #
    # Trackdown reports this trust state; it does not act on it. Deciding what an
    # unverified location may be used for is your application's call.
    def verify_request_came_through_trusted_cloudflare_path_with(verifier = nil, &block)
      verify_request_came_through_trusted_cdn_path_with(:cloudflare, verifier, &block)
    end

    def verify_request_came_through_trusted_cloudfront_path_with(verifier = nil, &block)
      verify_request_came_through_trusted_cdn_path_with(:cloudfront, verifier, &block)
    end

    # Provider-aware lower-level form used by the two plain-English helpers above.
    def verify_request_came_through_trusted_cdn_path_with(provider_name, verifier = nil, &block)
      validate_trusted_cdn_provider!(provider_name)
      verifier ||= block

      if verifier.nil?
        raise ArgumentError, "verify_request_came_through_trusted_#{provider_name}_path_with needs a block or " \
                             'a callable saying how you know a request came through that CDN'
      end

      unless verifier.respond_to?(:call)
        raise ArgumentError, "The trusted #{provider_name} path verifier must respond to #call " \
                             "(a block, proc, lambda, or any callable object), got: #{verifier.inspect}"
      end

      @verifier_mutex.synchronize do
        @warned_verifier_raised.delete(provider_name)
        @trusted_cdn_path_verifiers[provider_name] = verifier
      end
    end

    # Did the host vouch for this request? Asked fresh every time, never cached,
    # and a verifier that blows up means "no" — a geolocation lookup must not be
    # able to take an application down.
    def request_came_through_trusted_cdn_path?(request, provider_name:)
      validate_trusted_cdn_provider!(provider_name)
      verifier = trusted_cdn_path_verifier_for(provider_name)
      return false unless request && verifier

      begin
        !!verifier.call(request)
      rescue StandardError => e
        warn_verifier_raised(provider_name, e)
        false
      end
    end

    def trusted_cdn_path_verifier_for(provider_name)
      validate_trusted_cdn_provider!(provider_name)
      @verifier_mutex.synchronize { @trusted_cdn_path_verifiers[provider_name] }
    end

    private

    def validate_trusted_cdn_provider!(provider_name)
      return if TRUSTED_CDN_PROVIDERS.include?(provider_name)

      raise ArgumentError, "Invalid trusted CDN provider: #{provider_name.inspect}. " \
                           "Must be one of: #{TRUSTED_CDN_PROVIDERS.join(', ')}"
    end

    def warn_verifier_raised(provider_name, error)
      should_warn = @verifier_mutex.synchronize do
        next false if @warned_verifier_raised[provider_name]

        @warned_verifier_raised[provider_name] = true
        true
      end
      return unless should_warn

      message = "[Trackdown] Your trusted #{provider_name} path verifier raised " \
                "#{error.class}: #{error.message}. Treating the #{provider_name} request source as :unverified."

      defined?(Rails) ? Rails.logger.error(message) : warn(message)
    end
  end
end
