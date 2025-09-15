# frozen_string_literal: true

require "rails/engine"
require_relative "../utils/rails_detection"

##
# Rails Engine for A2A integration
#
# This engine provides automatic integration with Rails applications,
# including middleware setup, route generation, and configuration management.
#
# @example Basic usage in Rails application
#   # config/application.rb
#   require 'a2a/rails'
#
#   class Application < Rails::Application
#     config.a2a.enabled = true
#     config.a2a.mount_path = '/a2a'
#   end
#
module A2A
  module Rails
    class Engine < Rails::Engine
      extend A2A::Utils::RailsDetection

      isolate_namespace A2A::Rails

      # Configure generators for Rails integration
      config.generators do |g|
        g.test_framework :rspec, fixture: false
        g.fixture_replacement :factory_bot, dir: "spec/factories"
        g.assets false
        g.helper false
        g.stylesheets false
        g.javascripts false
      end

      # A2A-specific configuration
      config.a2a = ActiveSupport::OrderedOptions.new
      config.a2a.enabled = false
      config.a2a.mount_path = "/a2a"
      config.a2a.auto_mount = true
      config.a2a.middleware_enabled = true
      config.a2a.authentication_required = false
      config.a2a.cors_enabled = true
      config.a2a.rate_limiting_enabled = false
      config.a2a.logging_enabled = true

      # Initialize A2A configuration
      initializer "a2a.configuration", before: :load_config_initializers do |app|
        A2A.configure do |config|
          config.rails_integration = app.config.a2a.enabled
          config.mount_path = app.config.a2a.mount_path
          config.authentication_required = app.config.a2a.authentication_required
          config.cors_enabled = app.config.a2a.cors_enabled
          config.rate_limiting_enabled = app.config.a2a.rate_limiting_enabled
          config.logging_enabled = app.config.a2a.logging_enabled
        end
      end

      # Set up middleware stack
      initializer "a2a.middleware", after: "a2a.configuration" do |app|
        if app.config.a2a.enabled && app.config.a2a.middleware_enabled
          # Add CORS middleware if enabled
          if app.config.a2a.cors_enabled
            app.middleware.insert_before ActionDispatch::Static, A2A::Server::Middleware::CorsMiddleware
          end

          # Add authentication middleware if required
          app.middleware.use A2A::Server::Middleware::AuthenticationMiddleware if app.config.a2a.authentication_required

          # Add rate limiting middleware if enabled
          app.middleware.use A2A::Server::Middleware::RateLimitMiddleware if app.config.a2a.rate_limiting_enabled

          # Add logging middleware if enabled
          app.middleware.use A2A::Server::Middleware::LoggingMiddleware if app.config.a2a.logging_enabled
        end
      end

      # Set up routes
      initializer "a2a.routes", after: "a2a.middleware" do |app|
        if app.config.a2a.enabled && app.config.a2a.auto_mount
          app.routes.prepend do
            mount A2A::Rails::Engine => app.config.a2a.mount_path
          end
        end
      end

      # Load A2A helpers into ActionController
      initializer "a2a.controller_helpers", after: "a2a.routes" do
        ActiveSupport.on_load(:action_controller_base) do
          include A2A::Rails::ControllerHelpers if A2A.config.rails_integration
        end

        ActiveSupport.on_load(:action_controller_api) do
          include A2A::Rails::ControllerHelpers if A2A.config.rails_integration
        end
      end

      # Configure Rails compatibility
      initializer "a2a.rails_compatibility" do |_app|
        # Ensure compatibility with Rails 6.0+
        if rails_version_supported?
          # Configure zeitwerk autoloading
          config.autoload_paths << File.expand_path("..", __dir__)

          # Set up eager loading for production
          config.eager_load_paths << File.expand_path("..", __dir__) if rails_production?
        end

        # Configure CSRF protection exemption for A2A endpoints
        if defined?(ActionController::Base)
          ActionController::Base.class_eval do
            protect_from_forgery except: :a2a_rpc, if: -> { A2A.config.rails_integration }
          end
        end
      end

      # Define engine routes
      routes.draw do
        # JSON-RPC endpoint
        post "/rpc", to: "a2a#rpc", as: :rpc

        # Agent card endpoints
        get "/agent-card", to: "a2a#agent_card", as: :agent_card
        get "/capabilities", to: "a2a#capabilities", as: :capabilities

        # Authenticated agent card endpoint
        get "/authenticated-agent-card", to: "a2a#authenticated_agent_card", as: :authenticated_agent_card

        # Health check endpoint
        get "/health", to: "a2a#health", as: :health

        # Server-Sent Events endpoint for streaming
        get "/stream/:task_id", to: "a2a#stream", as: :stream

        # Push notification webhook endpoint
        post "/webhook/:task_id", to: "a2a#webhook", as: :webhook
      end

      # Rake tasks
      rake_tasks do
        load File.expand_path("tasks/a2a.rake", __dir__)
      end

      # Generators
      generators do
        require_relative "generators/install_generator"
        require_relative "generators/agent_generator"
        require_relative "generators/migration_generator"
      end

      # Validate configuration
      def self.validate_configuration!(app)
        unless rails_version_supported?
          raise A2A::Errors::ConfigurationError,
                "A2A Rails integration requires Rails 6.0 or higher. Current version: #{rails_version}"
        end

        return unless app.config.a2a.enabled && !app.config.a2a.mount_path.start_with?("/")

        raise A2A::Errors::ConfigurationError,
              "A2A mount path must start with '/'. Got: #{app.config.a2a.mount_path}"
      end
    end
  end
end
