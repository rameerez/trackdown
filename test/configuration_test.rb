# frozen_string_literal: true

require 'test_helper'

class ConfigurationTest < Minitest::Test
  def setup
    Trackdown.instance_variable_set(:@configuration, nil)
    if defined?(Rails) && !Rails.respond_to?(:root)
      Rails.define_singleton_method(:root) { Pathname.new(Dir.pwd) }
    end
  end

  def test_default_database_path_without_rails
    Object.send(:remove_const, :Rails) if defined?(Rails)
  rescue NameError
    # ignore
  ensure
    config = Trackdown.configuration
    # default should be string under db/
    assert_match(%r{db/GeoLite2-City\.mmdb\z}, config.database_path)
  end

  def test_default_database_path_with_rails
    fake_root = File.expand_path('tmp/rails_root', __dir__)
    FileUtils.mkdir_p(File.join(fake_root, 'db'))

    rails_mock = Class.new do
      def self.root
        Pathname.new(@root)
      end
    end
    rails_mock.instance_variable_set(:@root, fake_root)

    Object.send(:remove_const, :Rails) if defined?(Rails)
    Object.const_set(:Rails, rails_mock)

    Trackdown.instance_variable_set(:@configuration, nil)
    config = Trackdown.configuration
    assert_equal File.join(fake_root, 'db', 'GeoLite2-City.mmdb'), config.database_path
  ensure
    Object.send(:remove_const, :Rails) if defined?(Rails)
  end

  def test_reject_private_ips_predicate
    config = Trackdown.configuration
    assert_equal true, config.reject_private_ips?
    config.reject_private_ips = false
    assert_equal false, config.reject_private_ips?
  end
end