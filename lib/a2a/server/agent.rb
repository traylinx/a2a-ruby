# frozen_string_literal: true

require_relative "../protocol/capability"

module A2A::Server
  ##
  # Agent DSL for defining A2A-compatible methods and capabilities
  #
  # This module provides a DSL for defining agent methods that can be called
  # via the A2A protocol. It includes method registration, capability definition,
  # parameter validation, and middleware support.
  #
  # @example Basic agent definition
  #   class MyAgent
  #     include A2A::Server::Agent
  #
  #     a2a_method "greet" do |params|
  #       { message: "Hello, #{params['name']}!" }
  #     end
  #
  #     a2a_capability "greeting" do
  #       method "greet"
  #       description "Greet a user by name"
  #       input_schema type: "object", properties: { name: { type: "string" } }
  #       output_schema type: "object", properties: { message: { type: "string" } }
  #     end
  #   end
  #
  module Agent
    def self.included(base)
      base.extend(ClassMethods)

      # Initialize class-level storage for A2A methods and capabilities
      if defined?(ActiveSupport) && base.respond_to?(:class_attribute)
        # Use ActiveSupport's class_attribute if available
        base.class_attribute :_a2a_methods, default: {}
        base.class_attribute :_a2a_capabilities, default: A2A::Protocol::CapabilityRegistry.new
        base.class_attribute :_a2a_config, default: {}
        base.class_attribute :_a2a_middleware, default: []
      else
        # Fallback implementation without ActiveSupport
        base.instance_variable_set(:@_a2a_methods, {})
        base.instance_variable_set(:@_a2a_capabilities, A2A::Protocol::CapabilityRegistry.new)
        base.instance_variable_set(:@_a2a_config, {})
        base.instance_variable_set(:@_a2a_middleware, [])

        # Define accessor methods
        base.define_singleton_method(:_a2a_methods) { @_a2a_methods }
        base.define_singleton_method(:_a2a_capabilities) { @_a2a_capabilities }
        base.define_singleton_method(:_a2a_config) { @_a2a_config }
        base.define_singleton_method(:_a2a_middleware) { @_a2a_middleware }
      end
    end

    module ClassMethods
      ##
      # Define an A2A method that can be called via JSON-RPC
      #
      # @param name [String] The method name
      # @param options [Hash] Method options
      # @option options [Boolean] :streaming Whether the method supports streaming
      # @option options [Boolean] :async Whether the method supports async execution
      # @option options [Array<String>] :security Required security schemes
      # @option options [Hash] :metadata Additional method metadata
      # @yield [params, context] The method implementation block
      # @yieldparam params [Hash] The method parameters
      # @yieldparam context [A2A::Server::Context] The request context
      # @yieldreturn [Object] The method result
      #
      # @example Define a simple method
      #   a2a_method "echo" do |params|
      #     { message: params['message'] }
      #   end
      #
      # @example Define a streaming method
      #   a2a_method "stream_data", streaming: true do |params, context|
      #     Enumerator.new do |yielder|
      #       10.times do |i|
      #         yielder << { count: i }
      #         sleep 0.1
      #       end
      #     end
      #   end
      #
      def a2a_method(name, **options, &block)
        raise ArgumentError, "Method name is required" if name.blank?
        raise ArgumentError, "Method block is required" unless block_given?

        method_name = name.to_s

        _a2a_methods[method_name] = {
          handler: block,
          options: options.dup,
          streaming: options[:streaming] || false,
          async: options[:async] || false,
          security: options[:security] || [],
          metadata: options[:metadata] || {}
        }
      end

      ##
      # Define a capability using the DSL
      #
      # @param name [String] The capability name
      # @yield Block for capability definition
      #
      # @example Define a capability
      #   a2a_capability "text_analysis" do
      #     method "analyze_text"
      #     description "Analyze text for sentiment and topics"
      #     input_schema type: "object", properties: { text: { type: "string" } }
      #     output_schema type: "object", properties: { sentiment: { type: "string" } }
      #     tags ["nlp", "analysis"]
      #     streaming_supported true
      #   end
      #
      def a2a_capability(name, &block)
        raise ArgumentError, "Capability name is required" if name.blank?
        raise ArgumentError, "Capability block is required" unless block_given?

        builder = CapabilityBuilder.new(name.to_s)
        builder.instance_eval(&block)
        capability = builder.build

        _a2a_capabilities.register(capability)
        capability
      end

      ##
      # Configure the agent
      #
      # @param options [Hash] Configuration options
      # @option options [String] :name Agent name
      # @option options [String] :description Agent description
      # @option options [String] :version Agent version
      # @option options [Array<String>] :default_input_modes Default input modes
      # @option options [Array<String>] :default_output_modes Default output modes
      # @option options [Hash] :metadata Additional metadata
      #
      # @example Configure agent
      #   a2a_config name: "My Agent",
      #              description: "A helpful agent",
      #              version: "1.0.0"
      #
      def a2a_config(**options)
        _a2a_config.merge!(options)
      end

      ##
      # Add middleware to the agent
      #
      # @param middleware_class [Class] The middleware class
      # @param options [Hash] Middleware options
      #
      # @example Add authentication middleware
      #   a2a_middleware AuthenticationMiddleware, required: true
      #
      def a2a_middleware(middleware_class, **options)
        _a2a_middleware << { class: middleware_class, options: options }
      end

      ##
      # Get all registered A2A methods
      #
      # @return [Hash] Hash of method name to method definition
      def a2a_method_registry
        _a2a_methods.dup
      end

      ##
      # Get the capability registry
      #
      # @return [A2A::Protocol::CapabilityRegistry] The capability registry
      def a2a_capability_registry
        _a2a_capabilities
      end

      ##
      # Check if a method is registered
      #
      # @param name [String] The method name
      # @return [Boolean] True if the method is registered
      def a2a_method_registered?(name)
        _a2a_methods.key?(name.to_s)
      end

      ##
      # Get method definition
      #
      # @param name [String] The method name
      # @return [Hash, nil] The method definition or nil if not found
      def a2a_method_definition(name)
        _a2a_methods[name.to_s]
      end
    end

    ##
    # Handle an A2A JSON-RPC request
    #
    # @param request [A2A::Protocol::Request] The JSON-RPC request
    # @param context [A2A::Server::Context, nil] The request context
    # @return [Hash] The JSON-RPC response
    def handle_a2a_request(request, context: nil)
      method_name = request.method
      method_def = self.class.a2a_method_definition(method_name)

      raise A2A::Errors::MethodNotFound, "Method '#{method_name}' not found" unless method_def

      # Create context if not provided
      context ||= A2A::Server::Context.new(request: request)

      # Validate security requirements
      validate_security_requirements(method_def, context)

      # Execute with middleware chain
      result = execute_with_middleware(method_def, request.params, context)

      # Build response
      A2A::Protocol::JsonRpc.build_response(result: result, id: request.id) unless request.notification?
    rescue A2A::Errors::A2AError => e
      # Return error response for A2A errors
      unless request.notification?
        A2A::Protocol::JsonRpc.build_error_response(
          code: e.code,
          message: e.message,
          data: e.data,
          id: request.id
        )
      end
    rescue StandardError => e
      # Convert other errors to internal errors
      unless request.notification?
        A2A::Protocol::JsonRpc.build_error_response(
          code: A2A::Protocol::JsonRpc::INTERNAL_ERROR,
          message: e.message,
          id: request.id
        )
      end
    end

    ##
    # Execute a method with the middleware chain
    #
    # @param method_def [Hash] The method definition
    # @param params [Hash] The method parameters
    # @param context [A2A::Server::Context] The request context
    # @return [Object] The method result
    def execute_with_middleware(method_def, params, context)
      # Build middleware chain
      middleware_chain = build_middleware_chain(method_def, context)

      # Execute the chain
      middleware_chain.call(params) do
        # Execute the actual method
        execute_method(method_def, params, context)
      end
    end

    ##
    # Execute the actual method implementation
    #
    # @param method_def [Hash] The method definition
    # @param params [Hash] The method parameters
    # @param context [A2A::Server::Context] The request context
    # @return [Object] The method result
    def execute_method(method_def, params, context)
      handler = method_def[:handler]

      # Call the handler with appropriate parameters
      case handler.arity
      when 0
        instance_exec(&handler)
      when 1
        instance_exec(params, &handler)
      when 2
        instance_exec(params, context, &handler)
      else
        # For methods with more parameters, pass params and context
        instance_exec(params, context, &handler)
      end
    end

    private

    ##
    # Validate security requirements for a method
    #
    # @param method_def [Hash] The method definition
    # @param context [A2A::Server::Context] The request context
    # @raise [A2A::Errors::AuthenticationRequired] If authentication is required but missing
    # @raise [A2A::Errors::AuthorizationFailed] If authorization fails
    def validate_security_requirements(method_def, context)
      security_requirements = method_def[:security] || []
      return if security_requirements.empty?

      # Check if any required security scheme is satisfied
      satisfied = security_requirements.any? do |scheme|
        context.authenticated_with?(scheme)
      end

      return if satisfied

      if context.authenticated?
        raise A2A::Errors::AuthorizationFailed, "Method requires one of: #{security_requirements.join(", ")}"
      end

      raise A2A::Errors::AuthenticationRequired,
        "Method requires authentication with: #{security_requirements.join(", ")}"
    end

    ##
    # Build the middleware chain for method execution
    #
    # @param method_def [Hash] The method definition
    # @param context [A2A::Server::Context] The request context
    # @return [Proc] The middleware chain
    def build_middleware_chain(_method_def, context)
      # Combine class-level and method-level middleware
      all_middleware = self.class._a2a_middleware.dup

      # Build the chain from the inside out
      chain = ->(_params, &block) { block.call }

      all_middleware.reverse_each do |middleware_def|
        middleware_class = middleware_def[:class]
        middleware_options = middleware_def[:options]

        # Create middleware instance
        middleware = middleware_class.new(**middleware_options)

        # Wrap the current chain
        current_chain = chain
        chain = lambda do |params, &block|
          middleware.call(params, context) do
            current_chain.call(params, &block)
          end
        end
      end

      chain
    end
  end

  ##
  # Builder class for capability DSL
  #
  class CapabilityBuilder
    def initialize(name)
      @name = name
      @attributes = {}
    end

    ##
    # Set the method name for this capability
    #
    # @param method_name [String] The A2A method name
    def method(method_name)
      @attributes[:method] = method_name
    end

    ##
    # Set the capability description
    #
    # @param desc [String] The description
    def description(desc)
      @attributes[:description] = desc
    end

    ##
    # Set the input schema
    #
    # @param schema [Hash] The JSON Schema for input validation
    def input_schema(schema)
      @attributes[:input_schema] = schema
    end

    ##
    # Set the output schema
    #
    # @param schema [Hash] The JSON Schema for output validation
    def output_schema(schema)
      @attributes[:output_schema] = schema
    end

    ##
    # Set capability tags
    #
    # @param tag_list [Array<String>] List of tags
    def tags(tag_list)
      @attributes[:tags] = tag_list
    end

    ##
    # Set security requirements
    #
    # @param requirements [Array<String>] List of required security schemes
    def security_requirements(requirements)
      @attributes[:security_requirements] = requirements
    end

    ##
    # Set additional metadata
    #
    # @param meta [Hash] Metadata hash
    def metadata(meta)
      @attributes[:metadata] = meta
    end

    ##
    # Set streaming support
    #
    # @param supported [Boolean] Whether streaming is supported
    def streaming_supported(supported = true)
      @attributes[:streaming_supported] = supported
    end

    ##
    # Set async support
    #
    # @param supported [Boolean] Whether async execution is supported
    def async_supported(supported = true)
      @attributes[:async_supported] = supported
    end

    ##
    # Add an example
    #
    # @param example [Hash] Example with input/output/description
    def example(example)
      @attributes[:examples] ||= []
      @attributes[:examples] << example
    end

    ##
    # Build the capability
    #
    # @return [A2A::Protocol::Capability] The built capability
    def build
      A2A::Protocol::Capability.new(
        name: @name,
        **@attributes
      )
    end
  end

  ##
  # Request context for A2A method execution
  #
  class Context
    attr_reader :request, :user, :session, :metadata

    def initialize(request: nil, user: nil, session: nil, metadata: {})
      @request = request
      @user = user
      @session = session
      @metadata = metadata
      @auth_schemes = {}
    end

    ##
    # Check if the request is authenticated
    #
    # @return [Boolean] True if authenticated
    def authenticated?
      !@auth_schemes.empty?
    end

    ##
    # Check if authenticated with a specific scheme
    #
    # @param scheme [String] The security scheme name
    # @return [Boolean] True if authenticated with the scheme
    def authenticated_with?(scheme)
      @auth_schemes.key?(scheme)
    end

    ##
    # Set authentication for a scheme
    #
    # @param scheme [String] The security scheme name
    # @param data [Object] Authentication data
    def set_authentication(scheme, data)
      @auth_schemes[scheme] = data
    end

    ##
    # Get authentication data for a scheme
    #
    # @param scheme [String] The security scheme name
    # @return [Object, nil] The authentication data
    def get_authentication(scheme)
      @auth_schemes[scheme]
    end

    ##
    # Set user information
    #
    # @param user [Object] User object or identifier
    def set_user(user)
      @user = user
    end

    ##
    # Set session information
    #
    # @param session [Object] Session object or identifier
    def set_session(session)
      @session = session
    end

    ##
    # Set metadata
    #
    # @param key [String, Symbol] Metadata key
    # @param value [Object] Metadata value
    def set_metadata(key, value)
      @metadata[key] = value
    end

    ##
    # Get metadata
    #
    # @param key [String, Symbol] Metadata key
    # @return [Object, nil] Metadata value
    def get_metadata(key)
      @metadata[key]
    end
  end
end
