# frozen_string_literal: true

require_relative "lib/trackdown/version"

Gem::Specification.new do |spec|
  spec.name = "trackdown"
  spec.version = Trackdown::VERSION
  spec.authors = ["rameerez"]
  spec.email = ["rubygems@rameerez.com"]

  spec.summary = "Geolocate IP addresses using verified Cloudflare or CloudFront headers, or MaxMind"
  spec.description = "Trackdown is a Ruby gem for IP geolocation in Rails applications. " \
                     "It reads request-bound location headers from Cloudflare and Amazon CloudFront, " \
                     "verifies CDN client-IP corroboration in automatic mode, or uses a local MaxMind " \
                     "database (BYOK). It returns country, city, emoji flag, region, continent, postal " \
                     "code, latitude, longitude, timezone, and related GeoIP fields."
  spec.homepage = "https://github.com/rameerez/trackdown"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["rubygems_mfa_required"] = "true"
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
  # Cloudflare and Amazon CloudFront providers require no additional gems.

  # Development dependencies are managed in the Gemfile
end
