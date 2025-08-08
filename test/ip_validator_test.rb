# frozen_string_literal: true

require 'test_helper'

class IpValidatorTest < Minitest::Test
  def test_validate_allows_nil
    assert_nil Trackdown::IpValidator.validate!(nil)
  end

  def test_validate_accepts_valid_ipv4
    assert_instance_of IPAddr, Trackdown::IpValidator.validate!('8.8.8.8')
  end

  def test_validate_accepts_valid_ipv6
    assert_instance_of IPAddr, Trackdown::IpValidator.validate!('2001:4860:4860::8888')
  end

  def test_validate_rejects_invalid
    error = assert_raises(Trackdown::IpValidator::InvalidIpError) do
      Trackdown::IpValidator.validate!('not.an.ip')
    end
    assert_match(/Invalid IP address format/i, error.message)
  end

  def test_private_ip_predicate_private
    assert_equal true, Trackdown::IpValidator.private_ip?('10.0.0.1')
    assert_equal true, Trackdown::IpValidator.private_ip?('192.168.1.1')
    assert_equal true, Trackdown::IpValidator.private_ip?('127.0.0.1')
  end

  def test_private_ip_predicate_public
    assert_equal false, Trackdown::IpValidator.private_ip?('8.8.8.8')
  end
end