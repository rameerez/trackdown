# frozen_string_literal: true

require 'test_helper'

class VersionTest < Minitest::Test
  def test_version_present
    refute_nil ::Trackdown::VERSION
    assert_match(/\A\d+\.\d+\.\d+\z/, ::Trackdown::VERSION)
  end
end