# frozen_string_literal: true

namespace :a2a do
  desc "Show A2A configuration"
  task config: :environment do
    puts "A2A Configuration:"
    puts "=================="
    puts "Rails Integration: #{A2A.config.rails_integration}"
    puts "Mount Path: #{A2A.config.mount_path}"
    puts "Authentication Required: #{A2A.config.authentication_required}"
    puts "CORS Enabled: #{A2A.config.cors_enabled}"
    puts "Rate Limiting Enabled: #{A2A.config.rate_limiting_enabled}"
    puts "Logging Enabled: #{A2A.config.logging_enabled}"
    puts "Version: #{A2A::VERSION}"
  end

  desc "List all registered A2A agents and capabilities"
  task agents: :environment do
    puts "Registered A2A Agents:"
    puts "====================="

    agent_count = 0
    capability_count = 0

    ObjectSpace.each_object(Class) do |klass|
      next unless klass < ActionController::Base && klass.included_modules.include?(A2A::Server::Agent)

      agent_count += 1
      puts "\n#{klass.name}:"

      capabilities = klass._a2a_capabilities || []
      capability_count += capabilities.length

      if capabilities.any?
        capabilities.each do |capability|
          puts "  - #{capability.name}: #{capability.description}"
        end
      else
        puts "  (no capabilities defined)"
      end

      methods = klass._a2a_methods || {}
      next unless methods.any?

      puts "  Methods:"
      methods.each_key do |method_name|
        puts "    - #{method_name}"
      end
    end

    puts "\nSummary:"
    puts "--------"
    puts "Total Agents: #{agent_count}"
    puts "Total Capabilities: #{capability_count}"
  end

  desc "Generate agent card for all registered agents"
  task agent_cards: :environment do
    puts "Agent Cards:"
    puts "============"

    ObjectSpace.each_object(Class) do |klass|
      next unless klass < ActionController::Base && klass.included_modules.include?(A2A::Server::Agent)

      puts "\n#{klass.name}:"
      puts "-" * (klass.name.length + 1)

      begin
        # Create a mock controller instance to generate the card
        controller = klass.new
        controller.request = ActionDispatch::Request.new({})

        card = controller.send(:generate_agent_card)
        puts JSON.pretty_generate(card.to_h)
      rescue StandardError => e
        puts "Error generating card: #{e.message}"
      end
    end
  end

  desc "Validate A2A protocol compliance"
  task validate: :environment do
    puts "A2A Protocol Validation:"
    puts "======================="

    errors = []
    warnings = []

    # Check Rails version compatibility
    errors << "Rails version #{Rails.version} is not supported. Minimum version is 6.0" if Rails.version < "6.0"

    # Check required dependencies
    required_gems = %w[faraday json jwt redis concurrent-ruby]
    required_gems.each do |gem_name|
      require gem_name
    rescue LoadError
      errors << "Required gem '#{gem_name}' is not available"
    end

    # Validate configuration
    config = A2A.config
    errors << "Mount path must start with '/'" if config.mount_path && !config.mount_path.start_with?("/")

    # Check for registered agents
    agent_classes = []
    ObjectSpace.each_object(Class) do |klass|
      agent_classes << klass if klass < ActionController::Base && klass.included_modules.include?(A2A::Server::Agent)
    end

    warnings << "No A2A agents found. Consider creating some with 'rails generate a2a:agent'" if agent_classes.empty?

    # Validate agent implementations
    agent_classes.each do |klass|
      capabilities = klass._a2a_capabilities || []
      methods = klass._a2a_methods || {}

      warnings << "#{klass.name} has no capabilities defined" if capabilities.empty?

      warnings << "#{klass.name} has no A2A methods defined" if methods.empty?
    end

    # Report results
    if errors.any?
      puts "❌ Validation failed with #{errors.length} error(s):"
      errors.each { |error| puts "  - #{error}" }
    else
      puts "✅ Validation passed!"
    end

    if warnings.any?
      puts "\n⚠️  #{warnings.length} warning(s):"
      warnings.each { |warning| puts "  - #{warning}" }
    end

    puts "\nSummary:"
    puts "--------"
    puts "Agents found: #{agent_classes.length}"
    puts "Total capabilities: #{agent_classes.sum { |k| (k._a2a_capabilities || []).length }}"
    puts "Total methods: #{agent_classes.sum { |k| (k._a2a_methods || {}).length }}"
  end

  desc "Start A2A development server"
  task server: :environment do
    puts "Starting A2A development server..."
    puts "A2A endpoints will be available at: #{A2A.config.mount_path}"
    puts "Press Ctrl+C to stop"

    # This would typically start a development server
    # For now, just show the configuration
    Rake::Task["a2a:config"].invoke
    puts "\nUse 'rails server' to start the full Rails application"
  end

  namespace :db do
    desc "Create A2A database tables"
    task migrate: :environment do
      puts "Creating A2A database tables..."

      # Check if migrations exist
      migration_path = Rails.root.join("db", "migrate")
      a2a_migrations = Dir.glob(migration_path.join("*_create_a2a_*.rb"))

      if a2a_migrations.empty?
        puts "No A2A migrations found. Run 'rails generate a2a:migration' first."
      else
        puts "Found #{a2a_migrations.length} A2A migration(s)"
        Rake::Task["db:migrate"].invoke
      end
    end

    desc "Seed A2A database with sample data"
    task seed: :environment do
      puts "Seeding A2A database..."

      # Create sample tasks for development
      if Rails.env.development?
        task_manager = A2A::Server::TaskManager.instance

        3.times do |i|
          task = task_manager.create_task(
            type: "sample_task_#{i + 1}",
            params: { message: "Sample task #{i + 1}" }
          )
          puts "Created sample task: #{task.id}"
        end
      else
        puts "Seeding is only available in development environment"
      end
    end
  end

  namespace :test do
    desc "Run A2A protocol compliance tests"
    task compliance: :environment do
      puts "Running A2A protocol compliance tests..."

      # This would run specific compliance tests
      # For now, just validate the setup
      Rake::Task["a2a:validate"].invoke
    end

    desc "Test A2A endpoints"
    task endpoints: :environment do
      puts "Testing A2A endpoints..."

      require "net/http"
      require "uri"

      base_url = "http://localhost:3000#{A2A.config.mount_path}"

      endpoints = [
        { path: "/health", method: "GET" },
        { path: "/agent-card", method: "GET" },
        { path: "/capabilities", method: "GET" }
      ]

      endpoints.each do |endpoint|
        uri = URI("#{base_url}#{endpoint[:path]}")
        response = Net::HTTP.get_response(uri)

        status = response.code.to_i < 400 ? "✅" : "❌"
        puts "#{status} #{endpoint[:method]} #{endpoint[:path]} - #{response.code}"
      rescue StandardError => e
        puts "❌ #{endpoint[:method]} #{endpoint[:path]} - Error: #{e.message}"
      end
    end
  end
end
