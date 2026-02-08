# frozen_string_literal: true

require "simplecov"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "trackdown"
require "minitest/autorun"
gem "minitest-mock"
require "minitest/mock"
require "minitest/reporters"
require "mocha/minitest"
require "webmock/minitest"

Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

# Disable actual HTTP requests
WebMock.disable_net_connect!(allow_localhost: true)

# Load support files
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

# Helper methods for all tests
class Minitest::Test
  include TestHelpers::MockRequest if defined?(TestHelpers::MockRequest)

  def setup
    # Reset configuration before each test
    Trackdown.instance_variable_set(:@configuration, nil)
  end

  def teardown
    # Clean up after each test
    Trackdown.instance_variable_set(:@configuration, nil)
  end
end
