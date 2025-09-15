# frozen_string_literal: true

# SimpleCov configuration for A2A Ruby SDK
# Following a2a-python coverage patterns

require "simplecov-lcov"

SimpleCov.start do
  # Output formats
  if ENV["CI"]
    formatter SimpleCov::Formatter::LcovFormatter
  else
    formatter SimpleCov::Formatter::MultiFormatter.new([
                                                         SimpleCov::Formatter::HTMLFormatter,
                                                         SimpleCov::Formatter::LcovFormatter
                                                       ])
  end

  # Coverage tracking
  enable_coverage :branch
  primary_coverage :line

  # Filters
  add_filter "/spec/"
  add_filter "/test/"
  add_filter "/vendor/"
  add_filter "/tmp/"
  add_filter "/coverage/"
  add_filter "/.bundle/"

  # Groups (matching a2a-python structure)
  add_group "Types", "lib/a2a/types"
  add_group "Protocol", "lib/a2a/protocol"
  add_group "Client", "lib/a2a/client"
  add_group "Server", "lib/a2a/server"
  add_group "Transport", "lib/a2a/transport"
  add_group "Utils", "lib/a2a/utils"
  add_group "Rails", "lib/a2a/rails"

  # Coverage thresholds (will be raised as implementation progresses)
  minimum_coverage 50
  minimum_coverage_by_file 5

  # Refuse to merge results older than 8 hours
  merge_timeout 28_800
end
