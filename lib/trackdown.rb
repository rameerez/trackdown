# frozen_string_literal: true

require_relative "trackdown/error"
require_relative "trackdown/version"
require_relative "trackdown/configuration"
require_relative "trackdown/ip_validator"
require_relative "trackdown/ip_locator"
require_relative "trackdown/database_updater"
require_relative "trackdown/location_result"
require_relative "trackdown/providers/base_provider"
require_relative "trackdown/providers/cloudflare_provider"
require_relative "trackdown/providers/maxmind_provider"
require_relative "trackdown/providers/auto_provider"

module Trackdown
  class << self
    attr_writer :configuration
  end

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.configure
    yield(configuration)
  end

  # Locate an IP address using the configured provider
  # @param ip [String] The IP address to locate
  # @param request [ActionDispatch::Request, nil] Optional Rails request object (required for Cloudflare provider)
  # @return [LocationResult] The location information
  def self.locate(ip, request: nil)
    IpLocator.locate(ip, request: request)
  end

  # Update the MaxMind database (only needed when using MaxMind provider)
  def self.update_database
    DatabaseUpdater.update
  end

  def self.database_exists?
    File.exist?(configuration.database_path)
  end

  # Legacy method - kept for backwards compatibility
  # New code should handle provider-specific errors instead
  def self.ensure_database_exists!
    unless database_exists?
      raise Error, "MaxMind database not found. Please set your MaxMind keys in config/initializers/trackdown.rb as described in the `trackdown` gem README, and then run Trackdown.update_database to download the MaxMind IP geolocation database."
    end
  end
end
