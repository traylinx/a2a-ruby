# frozen_string_literal: true

# frozen_string_literal: true

# Coverage configuration (equivalent to pytest-cov)
require "simplecov"
require "simplecov-lcov"

SimpleCov::Formatter::LcovFormatter.config do |c|
  c.report_with_single_file = true
  c.single_report_path = "coverage/lcov.info"
end

SimpleCov.start do
  if ENV["CI"]
    formatter SimpleCov::Formatter::LcovFormatter
  else
    formatter SimpleCov::Formatter::MultiFormatter.new([
      SimpleCov::Formatter::HTMLFormatter,
      SimpleCov::Formatter::LcovFormatter
    ])
  end
  
  add_filter "/spec/"
  add_filter "/vendor/"
  add_filter "/tmp/"
  
  # Group coverage by component (following a2a-python structure)
  add_group "Types", "lib/a2a/types"
  add_group "Protocol", "lib/a2a/protocol"
  add_group "Client", "lib/a2a/client"
  add_group "Server", "lib/a2a/server"
  add_group "Transport", "lib/a2a/transport"
  add_group "Utils", "lib/a2a/utils"
  
  # Track branches for comprehensive coverage
  enable_coverage :branch
  
  # Minimum coverage threshold (will be raised as implementation progresses)
  # Temporarily disabled for development
  # minimum_coverage 50
  # minimum_coverage_by_file 30
end

require "a2a"
require "webmock/rspec"
require "vcr"
require "factory_bot"

# Prevent real HTTP requests during tests (following a2a-python respx patterns)
WebMock.disable_net_connect!(
  allow_localhost: true,
  allow: %w[
    127.0.0.1
    localhost
    codeclimate.com
  ]
)

# VCR configuration for HTTP interaction recording
VCR.configure do |config|
  config.cassette_library_dir = "spec/fixtures/vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.default_cassette_options = {
    record: :once,
    allow_unused_http_interactions: false
  }
  
  # Filter sensitive data
  config.filter_sensitive_data("<FILTERED_TOKEN>") { |interaction| 
    interaction.request.headers["Authorization"]&.first
  }
end

# Performance testing gems (optional)
begin
  require "get_process_mem"
rescue LoadError
  # GetProcessMem not available - memory profiling tests will be skipped
end

begin
  require "allocation_tracer"
rescue LoadError
  # AllocationTracer not available - allocation tracking tests will be skipped
end

# Load support files in specific order
require_relative "support/a2a_helpers"
require_relative "support/matchers"
require_relative "support/test_doubles"
require_relative "support/fixture_generators"
require_relative "support/factory_bot"

# Load any additional support files
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure (equivalent to pytest markers)
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on Module and main
  config.disable_monkey_patching!

  # Use expect syntax only
  config.expect_with :rspec do |c|
    c.syntax = :expect
    c.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  # Mock configuration
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  # Shared context metadata behavior
  config.shared_context_metadata_behavior = :apply_to_host_groups

  # Filter configuration
  config.filter_run_when_matching :focus
  config.run_all_when_everything_filtered = true

  # Output configuration
  config.profile_examples = 10
  config.order = :random
  Kernel.srand config.seed

  # Include FactoryBot methods
  config.include FactoryBot::Syntax::Methods

  # Reset A2A configuration before each test
  config.before(:each) do
    A2A.reset_configuration!
  end

  # Clean up after tests
  config.after(:each) do
    WebMock.reset!
  end

  # Configure async testing (equivalent to pytest-asyncio)
  config.around(:each, :async) do |example|
    # For future async test support
    example.run
  end

  # Performance testing configuration
  config.before(:each, :performance) do
    # Warm up Ruby VM for more consistent performance measurements
    GC.start
    GC.disable if ENV['DISABLE_GC_DURING_PERFORMANCE_TESTS']
  end

  config.after(:each, :performance) do
    GC.enable if ENV['DISABLE_GC_DURING_PERFORMANCE_TESTS']
  end

  # Skip performance tests in CI unless explicitly requested
  config.filter_run_excluding :performance unless ENV['RUN_PERFORMANCE_TESTS']
  
  # Skip memory profiling tests if gems not available
  config.filter_run_excluding :memory unless defined?(GetProcessMem)
  
  # Skip load testing in normal test runs
  config.filter_run_excluding :load_testing unless ENV['RUN_LOAD_TESTS']
  
  # Skip regression tests unless baselines exist
  config.filter_run_excluding :regression unless ENV['RUN_REGRESSION_TESTS']
  
  # Skip interoperability tests unless explicitly requested
  config.filter_run_excluding :interoperability unless ENV['RUN_INTEROPERABILITY_TESTS']
end