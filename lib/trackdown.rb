# frozen_string_literal: true

require_relative "trackdown/version"
require_relative "trackdown/configuration"
require_relative "trackdown/ip_locator"
require_relative "trackdown/database_updater"

module Trackdown
  class Error < StandardError; end

  class << self
    attr_writer :configuration
  end

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.configure
    yield(configuration)
  end

  def self.locate(ip)
    IpLocator.locate(ip)
  end

  def self.update_database
    DatabaseUpdater.update
  end
end
