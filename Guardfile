# frozen_string_literal: true

# Guard configuration for A2A Ruby SDK
# Provides automatic testing similar to pytest watch mode

guard :rspec, cmd: "bundle exec rspec" do
  require "guard/rspec/dsl"
  dsl = Guard::RSpec::Dsl.new(self)

  # RSpec files
  rspec = dsl.rspec
  watch(rspec.spec_helper) { rspec.spec_dir }
  watch(rspec.spec_support) { rspec.spec_dir }
  watch(rspec.spec_files)

  # Ruby files
  ruby = dsl.ruby
  dsl.watch_spec_files_for(ruby.lib_files)

  # A2A-specific file patterns
  watch(%r{^lib/a2a/(.+)\.rb$}) { |m| "spec/a2a/#{m[1]}_spec.rb" }
  watch(%r{^lib/a2a/types/(.+)\.rb$}) { |m| "spec/a2a/types/#{m[1]}_spec.rb" }
  watch(%r{^lib/a2a/client/(.+)\.rb$}) { |m| "spec/a2a/client/#{m[1]}_spec.rb" }
  watch(%r{^lib/a2a/server/(.+)\.rb$}) { |m| "spec/a2a/server/#{m[1]}_spec.rb" }
  watch(%r{^lib/a2a/protocol/(.+)\.rb$}) { |m| "spec/a2a/protocol/#{m[1]}_spec.rb" }
  watch(%r{^lib/a2a/transport/(.+)\.rb$}) { |m| "spec/a2a/transport/#{m[1]}_spec.rb" }

  # Integration tests
  watch(%r{^lib/a2a/(.+)\.rb$}) { "spec/integration" }

  # Configuration changes
  watch("lib/a2a/configuration.rb") { "spec/a2a/configuration_spec.rb" }
  watch("lib/a2a.rb") { "spec/a2a_spec.rb" }
end
