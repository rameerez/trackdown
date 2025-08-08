# frozen_string_literal: true

require 'test_helper'
require 'timeout'

class IpLocatorTest < Minitest::Test
  def setup
    Trackdown.instance_variable_set(:@configuration, nil)
    # Provide minimal Rails stubs
    Object.const_set(:Rails, Module.new) unless defined?(::Rails)
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

    # Point to a fake existing database path and stub existence
    Trackdown.configuration.database_path = '/tmp/existent.mmdb'
    File.stubs(:exist?).with('/tmp/existent.mmdb').returns(true)

    # Ensure reader pool is rebuilt per test
    Trackdown::IpLocator.instance_variable_set(:@reader_pool, nil)
  end

  def teardown
    Trackdown::IpLocator.instance_variable_set(:@reader_pool, nil)
  end

  def with_stubbed_reader(record: nil, raise_error: nil)
    fake_reader = mock('MaxMind::DB Reader')
    if raise_error
      fake_reader.stubs(:get).raises(raise_error)
    else
      fake_reader.stubs(:get).with(any_parameters).returns(record)
    end

    fake_pool = mock('ConnectionPool')
    fake_pool.stubs(:with).yields(fake_reader)
    ConnectionPool.stubs(:new).yields(fake_reader).returns(fake_pool)
    MaxMind::DB.stubs(:new).returns(fake_reader)
  end

  def test_rejects_private_ips_when_configured
    Trackdown.configuration.reject_private_ips = true
    error = assert_raises(Trackdown::IpValidator::InvalidIpError) do
      Trackdown::IpLocator.send(:locate, '10.0.0.1')
    end
    assert_match(/Private IP addresses are not allowed/i, error.message)
  end

  def test_allows_private_ips_when_configured
    Trackdown.configuration.reject_private_ips = false
    with_stubbed_reader(record: nil)
    # will return Unknown result when no record
    result = Trackdown::IpLocator.send(:locate, '10.0.0.1')
    assert_equal 'Unknown', result.country_name
  end

  def test_timeout_raises_timeout_error
    Trackdown.configuration.timeout = 0.001

    fake_reader = mock('Reader')
    fake_reader.stubs(:get).with('8.8.8.8').returns(nil)

    fake_pool = mock('Pool')
    fake_pool.stubs(:with).yields(fake_reader)

    ConnectionPool.stubs(:new).returns(fake_pool)
    MaxMind::DB.stubs(:new).returns(fake_reader)
    Timeout.stubs(:timeout).with(Trackdown.configuration.timeout).raises(Timeout::Error)

    assert_raises(Trackdown::IpLocator::TimeoutError) do
      Trackdown::IpLocator.send(:fetch_record, '8.8.8.8')
    end
  end

  def test_database_error_wrapped
    with_stubbed_reader(raise_error: RuntimeError.new('boom'))
    error = assert_raises(Trackdown::IpLocator::DatabaseError) do
      Trackdown::IpLocator.send(:fetch_record, '8.8.8.8')
    end
    assert_match(/Database error: boom/, error.message)
  end

  def test_fetch_record_propagates_trackdown_errors
    with_stubbed_reader(raise_error: Trackdown::Error.new('oops'))
    assert_raises(Trackdown::Error) do
      Trackdown::IpLocator.send(:fetch_record, '8.8.8.8')
    end
  end

  def test_locate_with_nil_record_returns_unknown
    with_stubbed_reader(record: nil)
    result = Trackdown::IpLocator.send(:locate, '8.8.8.8')
    assert_nil result.country_code
    assert_equal 'Unknown', result.country_name
    assert_equal 'Unknown', result.city
    assert_equal '🏳️', result.flag_emoji
  end

  def test_extractors_happy_path
    record = {
      'country' => { 'iso_code' => 'US', 'names' => { 'en' => 'United States' } },
      'city' => { 'names' => { 'en' => 'Mountain View' } }
    }
    Trackdown::IpLocator.stubs(:fetch_record).returns(record)

    result = Trackdown::IpLocator.send(:locate, '8.8.8.8')
    assert_equal 'US', result.country_code
    assert_equal 'United States', result.country_name
    assert_equal 'Mountain View', result.city
    assert_equal '🇺🇸', result.flag_emoji
  end

  def test_extractors_fallbacks
    record = {
      'country' => { 'iso_code' => nil, 'names' => { 'es' => 'Estados Unidos' } },
      'city' => { 'names' => { 'es' => 'Roma' } }
    }
    Trackdown::IpLocator.stubs(:fetch_record).returns(record)

    result = Trackdown::IpLocator.send(:locate, '8.8.8.8')
    assert_nil result.country_code
    assert_equal 'Estados Unidos', result.country_name
    assert_equal 'Roma', result.city
    # With nil country_code, white flag should be returned
    assert_equal '🏳️', result.flag_emoji
  end

  def test_get_emoji_flag_maps_letters
    # private method, use send
    flag = Trackdown::IpLocator.send(:get_emoji_flag, 'US')
    assert_equal '🇺🇸', flag

    assert_equal '🏳️', Trackdown::IpLocator.send(:get_emoji_flag, nil)
  end
end