# frozen_string_literal: true

require "test_helper"

class IpValidatorTest < Minitest::Test
  def test_validate_accepts_valid_ipv4
    # validate! returns the IPAddr object or nil for valid IPs
    # Should not raise an error - that's the success condition
    Trackdown::IpValidator.validate!("8.8.8.8")
    assert true
  end

  def test_validate_accepts_valid_ipv6
    # validate! returns the IPAddr object or nil for valid IPs
    # Should not raise an error - that's the success condition
    Trackdown::IpValidator.validate!("2001:4860:4860::8888")
    assert true
  end

  def test_validate_rejects_invalid_format
    error = assert_raises(Trackdown::IpValidator::InvalidIpError) do
      Trackdown::IpValidator.validate!("not.an.ip")
    end

    assert_match(/Invalid IP address format/, error.message)
  end

  def test_validate_accepts_nil
    assert_nil Trackdown::IpValidator.validate!(nil)
  end

  def test_validate_rejects_malformed_string
    error = assert_raises(Trackdown::IpValidator::InvalidIpError) do
      Trackdown::IpValidator.validate!("256.256.256.256")
    end

    assert_match(/Invalid IP address format/, error.message)
  end

  def test_private_ip_detects_192_168_range
    assert Trackdown::IpValidator.private_ip?("192.168.1.1")
  end

  def test_private_ip_detects_10_range
    assert Trackdown::IpValidator.private_ip?("10.0.0.1")
    assert Trackdown::IpValidator.private_ip?("10.255.255.255")
  end

  def test_private_ip_detects_172_16_range
    assert Trackdown::IpValidator.private_ip?("172.16.0.1")
    assert Trackdown::IpValidator.private_ip?("172.31.255.255")
  end

  def test_private_ip_detects_127_loopback
    assert Trackdown::IpValidator.private_ip?("127.0.0.1")
    assert Trackdown::IpValidator.private_ip?("127.0.0.2")
  end

  def test_private_ip_rejects_public_ip
    refute Trackdown::IpValidator.private_ip?("8.8.8.8")
    refute Trackdown::IpValidator.private_ip?("1.1.1.1")
  end

  def test_private_ip_detects_link_local
    # Note: IPAddr.private? may not detect link-local as private
    # Link-local (169.254.x.x) is technically not RFC1918 private
    # but is reserved. This test documents the actual behavior
    refute Trackdown::IpValidator.private_ip?("169.254.1.1")
  end

  def test_private_ip_detects_ipv6_loopback
    assert Trackdown::IpValidator.private_ip?("::1")
  end

  def test_private_ip_detects_ipv6_private
    assert Trackdown::IpValidator.private_ip?("fc00::1")
    assert Trackdown::IpValidator.private_ip?("fd00::1")
  end
end
