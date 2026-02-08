# frozen_string_literal: true

source "https://rubygems.org"
gemspec

gem "rake", "~> 13.0"

group :development do
  gem "irb"
  gem "rubocop", "~> 1.0"
  gem "rubocop-minitest", "~> 0.35"
  gem "rubocop-performance", "~> 1.0"
end

group :development, :test do
  gem "appraisal"
  gem "minitest", "~> 6.0"
  gem "minitest-mock"
  gem "minitest-reporters", "~> 1.6"
  gem "mocha", "~> 2.0"
  gem "rack-test"
  gem "ostruct"
  gem "webmock", "~> 3.19"
  gem "simplecov", require: false

  # For testing MaxMind provider
  gem "maxmind-db", "~> 1.2"
  gem "connection_pool", "~> 2.4"
end
