Trackdown.configure do |config|
  config.maxmind_account_id = Rails.application.credentials.dig("maxmind", "account_id")
  config.maxmind_license_key = Rails.application.credentials.dig("maxmind", "license_key")
end
