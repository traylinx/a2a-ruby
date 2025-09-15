# frozen_string_literal: true

require_relative "a2a/modules"
require_relative "a2a/version"
require_relative "a2a/configuration"
require_relative "a2a/errors"
require_relative "a2a/types"
require_relative "a2a/plugin"
require_relative "a2a/plugin_manager"
require_relative "a2a/monitoring"

# Core protocol components (Task 2 - Core Protocol Implementation)
require_relative "a2a/protocol/json_rpc"

# Agent card system components (Task 3 - Agent Card System Implementation)
require_relative "a2a/protocol/capability"
require_relative "a2a/protocol/agent_card_server"

# Server components (Task 5 - Server-Side Components)
require_relative "a2a/server/agent"
require_relative "a2a/server/handler"
require_relative "a2a/server/request_handler"
require_relative "a2a/server/default_request_handler"
require_relative "a2a/server/middleware"
require_relative "a2a/server/task_manager"
require_relative "a2a/server/push_notification_manager"
require_relative "a2a/server/a2a_methods"

# Transport layer components (Task 7 - Transport Layer Implementation)
require_relative "a2a/transport/http"
require_relative "a2a/transport/sse"
require_relative "a2a/transport/grpc"

# Client components (Task 4 - Client-Side Components)
require_relative "a2a/client/base"
require_relative "a2a/client/config"
require_relative "a2a/client/http_client"
require_relative "a2a/client/auth"
require_relative "a2a/client/middleware"

# Rails integration (Task 8 - Rails Integration) - loaded conditionally
if defined?(Rails)
  require_relative "a2a/rails/engine"
  require_relative "a2a/rails/controller_helpers"
  require_relative "a2a/rails/a2a_controller"
end

##
# The A2A Ruby SDK
#
# This module provides a complete implementation of Google's Agent2Agent (A2A) Protocol
# for Ruby applications. It supports both client and server-side A2A implementations
# with multiple transport protocols.
#
# @example Basic client usage
#   client = A2A::Client::HttpClient.new("https://agent.example.com/a2a")
#   message = A2A::Types::Message.new(
#     message_id: SecureRandom.uuid,
#     role: "user",
#     parts: [A2A::Types::TextPart.new(text: "Hello, agent!")]
#   )
#   response = client.send_message(message)
#
# @example Basic server usage
#   class MyAgentController < ApplicationController
#     include A2A::Server::Agent
#
#     a2a_skill "greeting" do |skill|
#       skill.description = "Greet users"
#       skill.tags = ["greeting", "conversation"]
#     end
#
#     a2a_method "greet" do |params|
#       { message: "Hello, #{params[:name]}!" }
#     end
#   end
#
module A2A
  class << self
    # Global configuration for the A2A SDK
    # @return [A2A::Configuration]
    attr_accessor :configuration

    # Global plugin manager
    # @return [A2A::PluginManager]
    attr_accessor :plugin_manager

    # Configure the A2A SDK
    # @yield [config] Configuration block
    # @yieldparam config [A2A::Configuration] The configuration object
    def configure
      self.configuration ||= Configuration.new
      yield(configuration) if block_given?
      configuration.validate!
      configuration
    end

    # Configure from YAML file
    # @param file_path [String] Path to YAML configuration file
    # @param environment [String, nil] Environment section to load
    # @return [A2A::Configuration]
    def configure_from_file(file_path, environment: nil)
      self.configuration ||= Configuration.new
      configuration.load_from_file(file_path, environment: environment)
      configuration.validate!
      configuration
    end

    # Configure from environment variables only
    # @param environment [String, nil] Environment name
    # @return [A2A::Configuration]
    def configure_from_env(environment: nil)
      self.configuration = Configuration.new(environment: environment)
      configuration.validate!
      configuration
    end

    # Get the current configuration or create a default one
    # @return [A2A::Configuration]
    def config
      self.configuration ||= Configuration.new
    end

    # Reset configuration to defaults
    def reset_configuration!
      self.configuration = Configuration.new
    end

    # Create a child configuration with inheritance
    # @param **overrides [Hash] Configuration overrides
    # @return [A2A::Configuration]
    def child_config(**overrides)
      config.child(**overrides)
    end

    # Get the plugin manager
    # @return [A2A::PluginManager]
    def plugins
      self.plugin_manager ||= PluginManager.new(config)
    end

    # Register a plugin
    # @param name [Symbol] Plugin name
    # @param plugin_class [Class] Plugin class
    # @param **options [Hash] Plugin options
    def register_plugin(name, plugin_class, **options)
      A2A::Plugin.register(name, plugin_class, **options)
    end

    # Load a plugin
    # @param name [Symbol] Plugin name
    # @param **config [Hash] Plugin configuration
    def load_plugin(name, **config)
      plugins.load_plugin(name, **config)
    end

    # Configure plugins from hash
    # @param plugin_configs [Hash] Plugin configurations
    def configure_plugins(*args)
      plugins.configure_plugins(*args)
    end

    # Initialize monitoring system
    # @param config [A2A::Configuration] Configuration instance
    def initialize_monitoring!(config = self.config)
      A2A::Monitoring.initialize!(config)
    end

    # Get monitoring metrics
    # @return [A2A::Monitoring::MetricsCollector]
    def metrics
      A2A::Monitoring.metrics
    end

    # Get structured logger
    # @return [A2A::Monitoring::StructuredLogger]
    def logger
      A2A::Monitoring.logger
    end

    # Record a metric
    # @param name [String] Metric name
    # @param value [Numeric] Metric value
    # @param **labels [Hash] Metric labels
    def record_metric(name, value, **labels)
      A2A::Monitoring.record_metric(name, value, **labels)
    end

    # Time a block of code
    # @param name [String] Timer name
    # @param **labels [Hash] Timer labels
    # @yield Block to time
    # @return [Object] Block result
    def time(name, **labels, &block)
      A2A::Monitoring.time(name, **labels, &block)
    end
  end
end
