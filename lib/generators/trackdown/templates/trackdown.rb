# frozen_string_literal: true

Trackdown.configure do |config|
  # ========================================
  # Provider Selection
  # ========================================
  # Choose your IP geolocation provider:
  #
  # :auto (recommended, default)
  #   - Verifies CDN geolocation against the CDN's client-IP header
  #   - Supports Cloudflare and Amazon CloudFront
  #   - Falls back to MaxMind when neither CDN can be verified
  #   - Tries MaxMind, then Unknown, when both CDN candidates appear valid
  #
  # :cloudflare
  #   - Uses Cloudflare CF-IPCountry header
  #   - Requires: App behind Cloudflare + IP Geolocation enabled
  #   - Zero additional dependencies!
  #   - Must pass request object: Trackdown.locate(ip, request: request)
  #
  # :cloudfront
  #   - Uses Amazon CloudFront CloudFront-Viewer-* headers
  #   - Requires: a CloudFront origin request policy forwarding location headers
  #   - Requires: direct-origin access blocked before headers can be trusted
  #   - Must pass request object: Trackdown.locate(ip, request: request)
  #   - Exact AWS header contract:
  #     https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html#cloudfront-headers-viewer-location
  #
  # :maxmind
  #   - Uses MaxMind GeoLite2 database
  #   - Requires: maxmind-db and connection_pool gems
  #   - Requires: MaxMind account and database download
  #
  config.provider = :auto

  # ========================================
  # Cloudflare Setup (for :cloudflare or :auto providers)
  # ========================================
  # 1. Ensure your app is behind Cloudflare
  # 2. In Cloudflare dashboard → Network → Enable "IP Geolocation"
  #    OR under Rules → Transform Rules → Managed Transforms → Enable "Add visitor location headers"
  # 3. Use: Trackdown.locate(request.remote_ip, request: request)
  # 4. Restrict direct-origin traffic before trusting CF-* headers:
  #    https://developers.cloudflare.com/fundamentals/concepts/cloudflare-ip-addresses/#block-other-ip-addresses-recommended
  #    https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/
  #
  # No gems, API keys, or database are needed after the CDN/origin setup.

  # ========================================
  # Amazon CloudFront Setup (for :cloudfront or :auto providers)
  # ========================================
  # 1. Attach an origin request policy containing CloudFront's viewer-location
  #    headers and CloudFront-Viewer-Address. Exact AWS policy documentation:
  #    https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/controlling-origin-requests.html
  # 2. Restrict the origin so direct clients cannot forge CloudFront-* headers.
  #    AWS's exact custom-origin guidance:
  #    https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/add-origin-custom-headers.html
  #    https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-overview.html
  # 3. Use: Trackdown.locate(request.remote_ip, request: request)
  #
  # AWS's AllViewerAndCloudFrontHeaders-2022-06 managed policy includes the
  # required headers, but also forwards every viewer header, cookie, and query:
  # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-origin-request-policies.html#managed-origin-request-policy-all-viewer-and-cloudfront
  # Prefer a custom least-privilege policy, or explicitly select :cloudfront for
  # a secured deployment where both CDN header families intentionally coexist.

  # ========================================
  # MaxMind Setup (for :maxmind or :auto providers)
  # ========================================
  # Only needed if using MaxMind provider or as fallback
  #
  # 1. Add to Gemfile:
  #    gem 'maxmind-db'
  #    gem 'connection_pool'
  #
  # 2. Get your MaxMind account: https://www.maxmind.com/
  #
  # 3. Configure credentials (using Rails credentials recommended):
  config.maxmind_account_id = Rails.application.credentials.dig(:maxmind, :account_id)
  config.maxmind_license_key = Rails.application.credentials.dig(:maxmind, :license_key)
  #
  # 4. Run: Trackdown.update_database
  #
  # 5. Schedule regular updates (MaxMind updates Tue/Fri):
  #    Add to config/recurring.yml (for solid_queue):
  #    refresh_trackdown_database:
  #      class: TrackdownDatabaseRefreshJob
  #      schedule: every Saturday at 4am

  # Optional: Database location (defaults to db/GeoLite2-City.mmdb)
  # config.database_path = Rails.root.join('db', 'GeoLite2-City.mmdb').to_s

  # Optional: MaxMind performance tuning
  # config.timeout = 3        # Lookup timeout (seconds)
  # config.pool_size = 5      # Connection pool size
  # config.pool_timeout = 3   # Pool wait timeout (seconds)
  # config.memory_mode = MaxMind::DB::MODE_MEMORY # or MODE_FILE to reduce memory

  # ========================================
  # Trusted CDN Path Verification (optional, provider-specific)
  # ========================================
  # CDN geolocation headers are just headers: anyone who can reach an
  # unprotected origin directly can send you a convincing set of them. Trackdown
  # therefore marks every request-backed result :unverified unless you tell it
  # how *you* know the request really came through that specific CDN. Keep these
  # checks separate: a trusted CloudFront request must not authenticate CF-*
  # headers that CloudFront forwarded from a viewer, and vice versa.
  #
  # Cloudflare example: have the ingress/middleware that actually checked
  # Authenticated Origin Pulls or the Cloudflare peer network set this private
  # Rack-environment flag. A viewer must never be able to set it:
  #
  # config.verify_request_came_through_trusted_cloudflare_path_with do |request|
  #   request.env['my_app.cloudflare_origin_was_verified'] == true
  # end
  #
  # CloudFront example: require the origin-only custom header configured on the
  # distribution. Refuse to boot if the expected secret is absent, and require
  # a non-empty supplied value before comparing:
  #
  # expected_cloudfront_origin_secret =
  #   Rails.application.credentials.dig(:cloudfront, :origin_secret).to_s
  # raise 'Missing CloudFront origin secret' if expected_cloudfront_origin_secret.empty?
  #
  # config.verify_request_came_through_trusted_cloudfront_path_with do |request|
  #   supplied_cloudfront_origin_secret =
  #     request.env['HTTP_X_CLOUDFRONT_ORIGIN_SECRET'].to_s
  #
  #   !supplied_cloudfront_origin_secret.empty? &&
  #     ActiveSupport::SecurityUtils.secure_compare(
  #       supplied_cloudfront_origin_secret,
  #       expected_cloudfront_origin_secret
  #     )
  # end
  #
  # Both empty checks matter: Rails secure_compare('', '') is true because the
  # implementation checks equal byte lengths and then compares the bytes:
  # https://api.rubyonrails.org/classes/ActiveSupport/SecurityUtils.html#method-c-secure_compare
  #
  # Results then report `source_trust` as :host_verified instead of :unverified,
  # and `source_was_verified_by_host?` becomes true. Trackdown reports this; it
  # does not act on it. Deciding what an unverified location may be used for is
  # your application's call.
  #
  # https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/
  # https://developers.cloudflare.com/fundamentals/concepts/cloudflare-ip-addresses/#block-other-ip-addresses-recommended
  # https://developers.cloudflare.com/fundamentals/reference/http-headers/#request-headers
  # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/add-origin-custom-headers.html
  # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-overview.html
  # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-origin-request-policies.html#managed-origin-request-policy-all-viewer-and-cloudfront

  # ========================================
  # General Options
  # ========================================
  # Reject private/local IP addresses (192.168.x.x, 127.0.0.1, etc.)
  # config.reject_private_ips = true
end
