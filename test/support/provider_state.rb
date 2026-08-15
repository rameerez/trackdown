# frozen_string_literal: true

require 'stringio'

module TestHelpers
  module ProviderState
    # AutoProvider warns once per process, so every test case has to start fresh.
    def reset_auto_provider_warnings
      provider = Trackdown::Providers::AutoProvider
      provider.instance_variable_set(:@warned_ip_mismatch, false)
      provider.instance_variable_set(:@warned_ambiguous_edge, false)
      provider.instance_variable_set(:@warned_no_providers, false)
    end

    # Run a block with stderr captured, and hand back whatever it printed.
    def capture_stderr
      original = $stderr
      $stderr = StringIO.new
      yield
      $stderr.string
    ensure
      $stderr = original
    end

    # Run a block whose warnings we expect and don't care to read.
    def without_warnings
      original = $stderr
      $stderr = StringIO.new
      yield
    ensure
      $stderr = original
    end

    # Run a block in verbose mode and hand back everything Ruby itself complained
    # about — a library must not make an application's logs noisy over input an
    # attacker chose.
    def capture_ruby_warnings
      original_verbose = $VERBOSE
      $VERBOSE = true
      capture_stderr { yield }
    ensure
      $VERBOSE = original_verbose
    end
  end
end
