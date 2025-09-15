# frozen_string_literal: true

##
# Plugin architecture for extending A2A functionality
#
# Provides extension points for custom functionality including:
# - Custom transport protocols
# - Authentication strategies
# - Request/response processing hooks
# - Middleware components
#
# @example Register a plugin
#   A2A::Plugin.register(:my_plugin, MyPlugin)
#
# @example Create a transport plugin
#   class MyTransport < A2A::Plugin::Base
#     plugin_type :transport
#
#     def send_request(request)
#       # Custom transport implementation
#     end
#   end
#
module A2A::Plugin
  class << self
    # Registry of all plugins
    # @return [Hash<Symbol, Hash>]
    attr_reader :registry

    # Registered hooks
    # @return [Hash<Symbol, Array>]
    attr_reader :hooks

    # Initialize plugin system
    def initialize!
      @registry = {}
      @hooks = Hash.new { |h, k| h[k] = [] }
      @loaded_plugins = Set.new
    end

    # Register a plugin
    # @param name [Symbol] Plugin name
    # @param plugin_class [Class] Plugin class
    # @param **options [Hash] Plugin options
    def register(name, plugin_class, **options)
      initialize! unless @registry

      unless plugin_class.respond_to?(:plugin_type)
        raise A2A::Errors::PluginError, "Plugin class must include A2A::Plugin::Base"
      end

      @registry[name] = {
        class: plugin_class,
        type: plugin_class.plugin_type,
        options: options,
        loaded: false
      }

      A2A.config.logger&.info("Registered plugin: #{name} (#{plugin_class.plugin_type})")
    end

    # Load a plugin
    # @param name [Symbol] Plugin name
    # @param **config [Hash] Plugin configuration
    # @return [Object] Plugin instance
    def load(name, **config)
      initialize! unless @registry

      plugin_info = @registry[name]
      raise A2A::Errors::PluginError, "Plugin not found: #{name}" unless plugin_info

      return plugin_info[:instance] if plugin_info[:loaded]

      begin
        instance = plugin_info[:class].new(**config)
        plugin_info[:instance] = instance
        plugin_info[:loaded] = true
        @loaded_plugins << name

        # Register plugin hooks
        instance.register_hooks(self) if instance.respond_to?(:register_hooks)

        A2A.config.logger&.info("Loaded plugin: #{name}")
        instance
      rescue StandardError => e
        raise A2A::Errors::PluginError, "Failed to load plugin #{name}: #{e.message}"
      end
    end

    # Unload a plugin
    # @param name [Symbol] Plugin name
    def unload(name)
      initialize! unless @registry

      plugin_info = @registry[name]
      return unless plugin_info && plugin_info[:loaded]

      instance = plugin_info[:instance]

      # Call cleanup if available
      instance.cleanup if instance.respond_to?(:cleanup)

      plugin_info[:loaded] = false
      plugin_info[:instance] = nil
      @loaded_plugins.delete(name)

      A2A.config.logger&.info("Unloaded plugin: #{name}")
    end

    # Get loaded plugins by type
    # @param type [Symbol] Plugin type
    # @return [Array<Object>] Plugin instances
    def loaded_plugins(type: nil)
      initialize! unless @registry

      plugins = @loaded_plugins.filter_map { |name| @registry[name][:instance] }

      if type
        plugins.select { |plugin| plugin.class.plugin_type == type }
      else
        plugins
      end
    end

    # Register a hook
    # @param event [Symbol] Hook event name
    # @param callable [Proc, Method] Hook handler
    # @param priority [Integer] Hook priority (lower = higher priority)
    def add_hook(event, callable, priority: 50)
      initialize! unless @hooks

      @hooks[event] << { callable: callable, priority: priority }
      @hooks[event].sort_by! { |hook| hook[:priority] }
    end

    # Execute hooks for an event
    # @param event [Symbol] Hook event name
    # @param *args [Array] Arguments to pass to hooks
    # @return [Array] Results from all hooks
    def execute_hooks(event, *args)
      initialize! unless @hooks

      results = []
      @hooks[event].each do |hook|
        result = hook[:callable].call(*args)
        results << result
      rescue StandardError => e
        A2A.config.logger&.error("Hook execution failed for #{event}: #{e.message}")
        raise A2A::Errors::PluginError, "Hook execution failed: #{e.message}"
      end
      results
    end

    # Check if a plugin is loaded
    # @param name [Symbol] Plugin name
    # @return [Boolean]
    def loaded?(name)
      initialize! unless @registry
      @loaded_plugins.include?(name)
    end

    # List all registered plugins
    # @return [Hash] Plugin registry information
    def list
      initialize! unless @registry

      @registry.transform_values do |info|
        {
          type: info[:type],
          loaded: info[:loaded],
          options: info[:options]
        }
      end
    end

    # Clear all plugins (for testing)
    def clear!
      @loaded_plugins&.each { |name| unload(name) }
      @registry&.clear
      @hooks&.clear
      initialize!
    end
  end

  ##
  # Base class for all A2A plugins
  #
  class Base
    class << self
      # Define plugin type
      # @param type [Symbol] Plugin type
      def plugin_type(type = nil)
        if type
          @plugin_type = type
        else
          @plugin_type
        end
      end

      # Define plugin dependencies
      # @param *deps [Array<Symbol>] Plugin dependencies
      def depends_on(*deps)
        @dependencies = deps
      end

      # Get plugin dependencies
      # @return [Array<Symbol>]
      def dependencies
        @dependencies || []
      end
    end

    # Initialize plugin
    # @param **config [Hash] Plugin configuration
    def initialize(**config)
      @config = config
      @logger = A2A.config.logger
      setup if respond_to?(:setup, true)
    end

    # Get plugin configuration
    # @return [Hash]
    attr_reader :config

    # Get logger instance
    # @return [Logger]
    attr_reader :logger

    # Register hooks (override in subclasses)
    # @param plugin_manager [A2A::Plugin] Plugin manager
    def register_hooks(plugin_manager)
      # Override in subclasses to register hooks
    end

    # Cleanup resources (override in subclasses)
    def cleanup
      # Override in subclasses for cleanup
    end
  end

  ##
  # Transport plugin interface
  #
  class TransportPlugin < Base
    plugin_type :transport

    # Send a request (must be implemented by subclasses)
    # @param request [Hash] Request data
    # @param **options [Hash] Transport options
    # @return [Object] Response
    def send_request(request, **options)
      raise NotImplementedError, "Transport plugins must implement #send_request"
    end

    # Check if transport supports streaming
    # @return [Boolean]
    def supports_streaming?
      false
    end

    # Create streaming connection (optional)
    # @param **options [Hash] Connection options
    # @return [Object] Stream connection
    def create_stream(**options)
      raise NotImplementedError, "Streaming not supported by this transport"
    end
  end

  ##
  # Authentication plugin interface
  #
  class AuthPlugin < Base
    plugin_type :auth

    # Authenticate a request (must be implemented by subclasses)
    # @param request [Hash] Request data
    # @param **options [Hash] Authentication options
    # @return [Hash] Authenticated request
    def authenticate_request(request, **options)
      raise NotImplementedError, "Auth plugins must implement #authenticate_request"
    end

    # Validate authentication (optional)
    # @param credentials [Object] Credentials to validate
    # @return [Boolean] Whether credentials are valid
    def validate_credentials(_credentials)
      true
    end
  end

  ##
  # Middleware plugin interface
  #
  class MiddlewarePlugin < Base
    plugin_type :middleware

    # Process request (must be implemented by subclasses)
    # @param request [Hash] Request data
    # @param next_middleware [Proc] Next middleware in chain
    # @return [Object] Response
    def call(request, next_middleware)
      raise NotImplementedError, "Middleware plugins must implement #call"
    end
  end

  ##
  # Hook events for plugin system
  #
  module Events
    # Request processing hooks
    BEFORE_REQUEST = :before_request
    AFTER_REQUEST = :after_request
    REQUEST_ERROR = :request_error

    # Response processing hooks
    BEFORE_RESPONSE = :before_response
    AFTER_RESPONSE = :after_response
    RESPONSE_ERROR = :response_error

    # Task lifecycle hooks
    TASK_CREATED = :task_created
    TASK_UPDATED = :task_updated
    TASK_COMPLETED = :task_completed
    TASK_FAILED = :task_failed

    # Agent card hooks
    AGENT_CARD_GENERATED = :agent_card_generated
    AGENT_CARD_REQUESTED = :agent_card_requested

    # All available events
    ALL = constants.map { |const| const_get(const) }.freeze
  end
end

# Add plugin error to errors module
##
# Plugin-related errors
#
class A2A::Errors::PluginErrorend
