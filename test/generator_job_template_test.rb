# frozen_string_literal: true

require 'test_helper'

class GeneratorJobTemplateTest < Minitest::Test
  def test_job_template_content
    path = File.expand_path('../lib/generators/trackdown/templates/trackdown_database_refresh_job.rb', __dir__)
    content = File.read(path)
    assert_includes content, 'class TrackdownDatabaseRefreshJob < ApplicationJob'
    assert_includes content, 'Trackdown.update_database'
  end
end