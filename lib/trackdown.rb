# frozen_string_literal: true

require_relative "trackdown/error"
require_relative "trackdown/version"
require_relative "trackdown/configuration"
require_relative "trackdown/ip_validator"
require_relative "trackdown/ip_locator"
require_relative "trackdown/database_updater"
require_relative "trackdown/location_result"

module Trackdown
  class << self
    attr_writer :configuration
  end

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.configure
    yield(configuration)
    configuration.validate!
  end

  def self.locate(ip)
    ensure_database_exists!
    IpLocator.locate(ip)
  end

  def self.update_database
    DatabaseUpdater.update
  end

  def self.database_exists?
    File.exist?(configuration.database_path)
  end

  def self.ensure_database_exists!
    unless database_exists?
      raise Error, "MaxMind database not found. Please set your MaxMind keys in config/initializers/trackdown.rb as described in the `trackdown` gem README, and then run Trackdown.update_database to download the MaxMind IP geolocation database."
    end
  end
end
