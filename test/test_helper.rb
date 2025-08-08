# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  enable_coverage :branch
  add_filter '/test/'
  add_filter '/bin/'
end

require 'minitest/autorun'
require 'minitest/reporters'
Minitest::Reporters.use!(Minitest::Reporters::SpecReporter.new)

require 'mocha/minitest'
require 'pathname'

# Provide a minimal Rails stub so gem code can reference Rails.root and Rails.logger safely
unless defined?(::Rails)
  module ::Rails; end
end
unless ::Rails.respond_to?(:root)
  ::Rails.define_singleton_method(:root) { Pathname.new(Dir.pwd) }
end
unless ::Rails.respond_to?(:logger)
  ::Rails.define_singleton_method(:logger) do
    @__td_logger__ ||= Object.new.tap do |o|
      def o.info(*); end
      def o.error(*); end
    end
  end
end

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'trackdown'