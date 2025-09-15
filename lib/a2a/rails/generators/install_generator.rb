# frozen_string_literal: true

require "rails/generators"
require "rails/generators/base"

##
# Rails generator for installing A2A integration
#
# This generator sets up the basic A2A configuration and files needed
# for Rails integration.
#
# @example
#   rails generate a2a:install
#   rails generate a2a:install --with-authentication
#   rails generate a2a:install --storage=redis
#
class A2A::Rails::Generators::InstallGenerator < Rails::Generators::Base
  source_root File.expand_path("templates", __dir__)

  class_option :with_authentication, type: :boolean, default: false,
    desc: "Generate authentication configuration"

  class_option :storage, type: :string, default: "memory",
    desc: "Storage backend (memory, database, redis)"

  class_option :mount_path, type: :string, default: "/a2a",
    desc: "Mount path for A2A endpoints"

  class_option :skip_routes, type: :boolean, default: false,
    desc: "Skip adding A2A routes"

  class_option :skip_initializer, type: :boolean, default: false,
    desc: "Skip creating initializer file"

  desc "Install A2A Rails integration"

  def create_initializer
    return if options[:skip_initializer]

    template "initializer.rb", "config/initializers/a2a.rb"
    say "Created A2A initializer", :green
  end

  def add_routes
    return if options[:skip_routes]

    route_content = generate_route_content

    if File.exist?("config/routes.rb")
      inject_into_file "config/routes.rb", after: "Rails.application.routes.draw do\n" do
        route_content
      end
      say "Added A2A routes", :green
    else
      say "Could not find config/routes.rb", :red
    end
  end

  def create_application_controller_example
    return unless options[:with_authentication]

    template "application_controller_with_auth.rb",
      "app/controllers/concerns/a2a_authentication.rb"
    say "Created A2A authentication concern", :green
  end

  def create_example_agent
    template "example_agent_controller.rb",
      "app/controllers/example_agent_controller.rb"
    say "Created example A2A agent controller", :green
  end

  def create_storage_configuration
    case options[:storage]
    when "database"
      create_database_storage
    when "redis"
      create_redis_storage
    else
      # Memory storage is default, no additional setup needed
      say "Using in-memory storage (default)", :yellow
    end
  end

  def add_gem_dependencies
    gem_content = []

    case options[:storage]
    when "database"
      gem_content << "# A2A database storage dependencies"
      gem_content << "gem 'activerecord', '>= 6.0'"
    when "redis"
      gem_content << "# A2A Redis storage dependencies"
      gem_content << "gem 'redis', '~> 5.0'"
      gem_content << "gem 'connection_pool', '~> 2.4'"
    end

    if options[:with_authentication]
      gem_content << "# A2A authentication dependencies"
      gem_content << "gem 'jwt', '~> 2.0'"
    end

    return unless gem_content.any?

    append_to_file "Gemfile" do
      "\n# A2A Ruby SDK dependencies\n#{gem_content.join("\n")}\n"
    end
    say "Added gem dependencies to Gemfile", :green
    say "Run 'bundle install' to install new dependencies", :yellow
  end

  def show_post_install_instructions
    say "\n#{"=" * 60}", :green
    say "A2A Rails integration installed successfully!", :green
    say "=" * 60, :green

    say "\nNext steps:", :yellow
    say "1. Run 'bundle install' if new gems were added"
    say "2. Review and customize config/initializers/a2a.rb"
    say "3. Check the example agent at app/controllers/example_agent_controller.rb"

    if options[:storage] == "database"
      say "4. Run 'rails generate a2a:migration' to create database tables"
      say "5. Run 'rails db:migrate' to apply migrations"
    end

    say "\nA2A endpoints will be available at:", :yellow
    say "  #{options[:mount_path]}/rpc (JSON-RPC)"
    say "  #{options[:mount_path]}/agent-card (Agent Card)"
    say "  #{options[:mount_path]}/health (Health Check)"

    say "\nFor more information, visit: https://a2a-protocol.org/sdk/ruby/", :blue
  end

  private

  def generate_route_content
    mount_path = options[:mount_path]

    <<~RUBY

      # A2A Protocol endpoints
      mount A2A::Rails::Engine => "#{mount_path}"

    RUBY
  end

  def create_database_storage
    template "migration.rb",
      "db/migrate/#{migration_timestamp}_create_a2a_tables.rb"
    say "Created A2A database migration", :green
  end

  def create_redis_storage
    template "redis_config.yml", "config/redis.yml"
    say "Created Redis configuration", :green
  end

  def migration_timestamp
    Time.current.strftime("%Y%m%d%H%M%S")
  end

  def authentication_strategy
    if options[:with_authentication]
      # Try to detect existing authentication gems
      if gem_exists?("devise")
        "devise"
      elsif gem_exists?("jwt")
        "jwt"
      else
        "api_key"
      end
    else
      "none"
    end
  end

  def gem_exists?(gem_name)
    File.read("Gemfile").include?(gem_name) if File.exist?("Gemfile")
  rescue StandardError
    false
  end

  def storage_backend
    options[:storage]
  end

  def mount_path
    options[:mount_path]
  end

  def with_authentication?
    options[:with_authentication]
  end

  def rails_version
    ::Rails.version
  end

  def a2a_version
    A2A::VERSION
  end
end
