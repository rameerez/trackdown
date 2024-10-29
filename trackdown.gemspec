# frozen_string_literal: true

require_relative "lib/trackdown/version"

Gem::Specification.new do |spec|
  spec.name = "trackdown"
  spec.version = Trackdown::VERSION
  spec.authors = ["rameerez"]
  spec.email = ["rubygems@rameerez.com"]

  spec.summary = "A Ruby gem for geolocating IP addresses using a MaxMind database"
  spec.description = "Trackdown is a Ruby gem that easily allows you to geolocate IP addresses. It's a simple, convenient wrapper on top of the MaxMind database. Plug your API keys and you're good to go. It keeps your MaxMind database updated regularly, and it offers a handy API for Rails applications to fetch country, city, and emoji flag information for any IP address."
  spec.homepage = "https://github.com/rameerez/trackdown"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  # spec.metadata["allowed_push_host"] = "TODO: Set to your gem server 'https://example.com'"

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

  spec.add_dependency "maxmind-db", "~> 1.1"
  spec.add_dependency "countries", "~> 7.0"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 1.21"
end
