# frozen_string_literal: true

require_relative "lib/trackdown/version"

Gem::Specification.new do |spec|
  spec.name = "trackdown"
  spec.version = Trackdown::VERSION
  spec.authors = ["rameerez"]
  spec.email = ["rubygems@rameerez.com"]

  spec.summary = "Get country, city, and emoji flag information for IP addresses using Cloudflare or MaxMind"
  spec.description = "Trackdown is a Ruby gem that easily allows you to geolocate IP addresses. It works out of the box with Cloudflare headers if you're using it, or you can use MaxMind (BYOK). The gem offers a clean API for Rails applications to fetch country, city, and emoji flag information for any IP address. Supports Cloudflare headers (instant, zero overhead) and MaxMind GeoLite2 database (offline capable)."
  spec.homepage = "https://github.com/rameerez/trackdown"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/rameerez/trackdown"
  spec.metadata["changelog_uri"] = "https://github.com/rameerez/trackdown/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Core dependencies (always required)
  spec.add_dependency "countries", "~> 7.0"

  # Optional dependencies (documented in README)
  # For MaxMind provider:
  #   gem 'maxmind-db', '~> 1.2'
  #   gem 'connection_pool', '~> 2.4'
  #
  # For Cloudflare provider: No additional gems required!

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rubocop", "~> 1.21"

  # Testing dependencies
  spec.add_development_dependency "minitest", "~> 5.25"
  spec.add_development_dependency "mocha", "~> 2.0"
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "webmock", "~> 3.0"

  # Optional dev dependencies for testing MaxMind provider
  spec.add_development_dependency "maxmind-db", "~> 1.2"
  spec.add_development_dependency "connection_pool", "~> 2.4"
end
