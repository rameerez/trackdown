# frozen_string_literal: true

require 'test_helper'

# Minimal stubs so the generator file can be loaded outside Rails
unless defined?(Rails)
  module Rails; end
end
module Rails::Generators
  class Base
    def self.source_root(path = nil); end

    def template(src, dest); end
    def append_to_file(path, content); end
    def create_file(path, content); end
    def say(message, *args); end
  end
end

require 'generators/trackdown/install_generator'

class GeneratorInstallTest < Minitest::Test
  class FakeGenerator < Trackdown::Generators::InstallGenerator
    public :create_initializer, :create_database_refresh_job, :add_mmdb_to_gitignore, :display_post_install_message

    def template(src, dest)
      @templates ||= {}
      @templates[dest] = src
    end

    def append_to_file(path, content)
      @appended ||= {}
      @appended[path] ||= String.new
      @appended[path] << content
    end

    def create_file(path, content)
      @created ||= {}
      @created[path] = content
    end

    def say(message, *args)
      (@messages ||= []) << message
    end

    attr_reader :templates, :appended, :created, :messages
  end

  def setup
    # Ensure Rails.root exists if referenced elsewhere
    Object.const_set(:Rails, Module.new) unless defined?(::Rails)
    ::Rails.define_singleton_method(:root) { Pathname.new(Dir.pwd) } unless ::Rails.respond_to?(:root)
  end

  def teardown
    # do not remove Rails; other tests may rely on it
  end

  def test_create_initializer_and_job
    gen = FakeGenerator.new
    gen.create_initializer
    gen.create_database_refresh_job

    assert_equal 'trackdown.rb', gen.templates['config/initializers/trackdown.rb']
    assert_equal 'trackdown_database_refresh_job.rb', gen.templates['app/jobs/trackdown_database_refresh_job.rb']
  end

  def test_add_mmdb_to_gitignore_appends_if_exists
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write('.gitignore', "node_modules\n")
        gen = FakeGenerator.new
        gen.add_mmdb_to_gitignore
        assert_includes gen.appended['.gitignore'], '*.mmdb'
      end
    end
  end

  def test_add_mmdb_to_gitignore_creates_if_missing
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.rm_f('.gitignore')
        gen = FakeGenerator.new
        gen.add_mmdb_to_gitignore
        assert_match(/\*\.mmdb/, gen.created['.gitignore'])
      end
    end
  end

  def test_display_post_install_message
    gen = FakeGenerator.new
    gen.display_post_install_message
    msgs = gen.messages.join("\n")
    assert_match(/successfully installed/i, msgs)
    assert_match(/configure your MaxMind credentials/i, msgs)
    assert_match(/Trackdown.update_database/i, msgs)
  end
end