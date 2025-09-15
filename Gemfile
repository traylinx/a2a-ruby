# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in a2a-ruby.gemspec
gemspec

gem "rake", "~> 13.0"

group :development, :test do
  gem "debug", platforms: %i[mri mingw x64_mingw]
  gem "pry", "~> 0.14"
  gem "pry-byebug", "~> 3.10"

  # Environment management
  gem "dotenv", "~> 2.8"
end

group :test do
  gem "factory_bot", "~> 6.0"
  gem "rspec", "~> 3.12"
  gem "rspec-rails", "~> 6.0"
  gem "simplecov", "~> 0.22"
  gem "simplecov-lcov", "~> 0.8"
  gem "vcr", "~> 6.0"
  gem "webmock", "~> 3.18"

  # Performance testing
  gem "benchmark-ips", "~> 2.12"
  gem "memory_profiler", "~> 1.0"
end

group :development do
  gem "rubocop", "~> 1.57"
  gem "rubocop-performance", "~> 1.19"
  gem "rubocop-rails", "~> 2.22"
  gem "rubocop-rspec", "~> 2.25"

  gem "guard", "~> 2.18"
  gem "guard-rspec", "~> 4.7"
  gem "yard", "~> 0.9"

  # Security auditing
  gem "bundler-audit", "~> 0.9"

  # Type checking (optional)
  gem "sorbet", "~> 0.5", require: false
  gem "sorbet-runtime", "~> 0.5"
  gem "tapioca", "~> 0.11", require: false
end
