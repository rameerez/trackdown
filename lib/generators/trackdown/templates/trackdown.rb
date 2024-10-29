# frozen_string_literal: true

Trackdown.configure do |config|
  # Required: Your MaxMind credentials
  config.maxmind_account_id = Rails.application.credentials.dig(:maxmind, :account_id)
  config.maxmind_license_key = Rails.application.credentials.dig(:maxmind, :license_key)

  # Optional: Configure database location (defaults to db/GeoLite2-City.mmdb)
  # config.database_path = Rails.root.join('db', 'GeoLite2-City.mmdb').to_s

  # Optional: Configure timeouts and pooling (defaults shown)
  # config.timeout = 3        # Timeout for individual lookups
  # config.pool_size = 5      # Size of the connection pool
  # config.pool_timeout = 3   # Timeout when waiting for a connection from the pool

  # Optional: Configure memory mode (defaults to MODE_MEMORY)
  # config.memory_mode = MaxMind::DB::MODE_FILE # Use MODE_FILE to reduce memory usage

  # Optional: Configure IP validation (defaults to true)
  # config.reject_private_ips = true  # Reject private/local IP addresses
end
