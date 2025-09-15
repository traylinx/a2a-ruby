# frozen_string_literal: true

require_relative "plugin"

##
# Plugin manager for loading and managing A2A plugins
#
# Handles plugin lifecycle, dependency resolution, and integration
# with the A2A framework components.
#
class A2A::PluginManager
  # Initialize plugin manager
  # @param config [A2A::Configuration] Configuration instance
  def initialize(config = A2A.config)
    @config = config
    @logger = config.logger
    @auto_load_plugins = []
    @plugin_configs = {}
  end

  # Configure auto-loading plugins
  # @param plugins [Hash<Symbol, Hash>] Plugin configurations
  def configure_plugins(plugins)
    @plugin_configs = plugins

    plugins.each do |name, plugin_config|
      @auto_load_plugins << name if plugin_config[:auto_load]
    end
  end

  # Load all configured plugins
  def load_all_plugins
    @auto_load_plugins.each do |plugin_name|
      load_plugin(plugin_name)
    end
  end

  # Load a specific plugin
  # @param name [Symbol] Plugin name
  # @param **config [Hash] Plugin configuration override
  def load_plugin(name, **config)
    plugin_config = @plugin_configs[name] || {}
    merged_config = plugin_config.merge(config)

    # Load dependencies first
    if A2A::Plugin.registry[name]
      dependencies = A2A::Plugin.registry[name][:class].dependencies
      dependencies.each do |dep|
        load_plugin(dep) unless A2A::Plugin.loaded?(dep)
      end
    end

    A2A::Plugin.load(name, **merged_config)
  rescue A2A::Errors::PluginError => e
    @logger&.error("Failed to load plugin #{name}: #{e.message}")
    raise
  end

  # Unload a plugin
  # @param name [Symbol] Plugin name
  def unload_plugin(name)
    A2A::Plugin.unload(name)
  end

  # Get transport plugins
  # @return [Array<A2A::Plugin::TransportPlugin>]
  def transport_plugins
    A2A::Plugin.loaded_plugins(type: :transport)
  end

  # Get authentication plugins
  # @return [Array<A2A::Plugin::AuthPlugin>]
  def auth_plugins
    A2A::Plugin.loaded_plugins(type: :auth)
  end

  # Get middleware plugins
  # @return [Array<A2A::Plugin::MiddlewarePlugin>]
  def middleware_plugins
    A2A::Plugin.loaded_plugins(type: :middleware)
  end

  # Find transport plugin by name
  # @param transport_name [String] Transport protocol name
  # @return [A2A::Plugin::TransportPlugin, nil]
  def find_transport(transport_name)
    transport_plugins.find do |plugin|
      plugin.respond_to?(:transport_name) &&
        plugin.transport_name == transport_name
    end
  end

  # Find auth plugin by name
  # @param auth_name [String] Authentication strategy name
  # @return [A2A::Plugin::AuthPlugin, nil]
  def find_auth_strategy(auth_name)
    auth_plugins.find do |plugin|
      plugin.respond_to?(:strategy_name) &&
        plugin.strategy_name == auth_name
    end
  end

  # Execute request hooks
  # @param event [Symbol] Hook event
  # @param request [Hash] Request data
  # @return [Hash] Modified request
  def execute_request_hooks(event, request)
    results = A2A::Plugin.execute_hooks(event, request)

    # Apply modifications from hooks
    results.each do |result|
      request.merge!(result) if result.is_a?(Hash)
    end

    request
  end

  # Execute response hooks
  # @param event [Symbol] Hook event
  # @param response [Object] Response data
  # @param request [Hash] Original request
  # @return [Object] Modified response
  def execute_response_hooks(event, response, request = nil)
    results = A2A::Plugin.execute_hooks(event, response, request)

    # Return last non-nil result or original response
    results.reverse.find { |result| !result.nil? } || response
  end

  # Create middleware chain from plugins
  # @return [Array<Proc>] Middleware chain
  def build_middleware_chain
    middleware_plugins.map do |plugin|
      proc { |request, next_middleware| plugin.call(request, next_middleware) }
    end
  end

  # Get plugin status
  # @return [Hash] Plugin status information
  def status
    {
      loaded_plugins: A2A::Plugin.loaded_plugins.size,
      registered_plugins: A2A::Plugin.registry.size,
      plugins_by_type: {
        transport: transport_plugins.size,
        auth: auth_plugins.size,
        middleware: middleware_plugins.size
      },
      auto_load_plugins: @auto_load_plugins,
      plugin_list: A2A::Plugin.list
    }
  end

  private

  attr_reader :config, :logger
end
