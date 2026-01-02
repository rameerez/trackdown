# frozen_string_literal: true

Trackdown.configure do |config|
  # ========================================
  # Provider Selection
  # ========================================
  # Choose your IP geolocation provider:
  #
  # :auto (recommended, default)
  #   - Tries Cloudflare first (instant, zero overhead)
  #   - Falls back to MaxMind if Cloudflare not available
  #   - Perfect for hybrid deployments
  #
  # :cloudflare
  #   - Uses Cloudflare CF-IPCountry header
  #   - Requires: App behind Cloudflare + IP Geolocation enabled
  #   - Zero additional dependencies!
  #   - Must pass request object: Trackdown.locate(ip, request: request)
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
  #
  # That's it! No gems, no API keys, no database needed.

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
  # General Options
  # ========================================
  # Reject private/local IP addresses (192.168.x.x, 127.0.0.1, etc.)
  # config.reject_private_ips = true
end
