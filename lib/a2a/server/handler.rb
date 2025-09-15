# frozen_string_literal: true

require_relative "../protocol/json_rpc"
require_relative "../errors"
require_relative "agent"
require_relative "middleware"

##
# Request handler for processing A2A JSON-RPC requests
#
# This class handles the processing of JSON-RPC requests, including
# method routing, parameter validation, response generation, and
# batch request processing.
#
# @example Basic usage
#   handler = A2A::Server::Handler.new(agent_instance)
#   response = handler.handle_request(json_request_string)
#
class A2A::Server::Handler
  attr_reader :agent, :middleware_stack

  ##
  # Initialize a new request handler
  #
  # @param agent [Object] The agent instance that includes A2A::Server::Agent
  # @param middleware [Array] Array of middleware to apply
  def initialize(agent, middleware: [])
    @agent = agent
    @middleware_stack = middleware.dup

    validate_agent!
  end

  ##
  # Handle a JSON-RPC request string
  #
  # @param request_body [String] The JSON-RPC request as a string
  # @param context [A2A::Server::Context, nil] Optional request context
  # @return [String] The JSON-RPC response as a string
  def handle_request(request_body, context: nil)
    A2A::Monitoring::Instrumentation.instrument_request({ method: "parse_request" }) do
      # Parse the JSON-RPC request
      parsed_request = A2A::Protocol::JsonRpc.parse_request(request_body)

      # Handle single or batch requests
      if parsed_request.is_a?(Array)
        handle_batch_request(parsed_request, context: context)
      else
        handle_single_request(parsed_request, context: context)
      end
    rescue A2A::Errors::A2AError => e
      # Return error response for A2A errors
      error_response = A2A::Protocol::JsonRpc.build_error_response(
        code: e.code,
        message: e.message,
        data: e.data,
        id: nil # Unknown ID for parse errors
      )
      error_response.to_json
    rescue StandardError => e
      # Return internal error for unexpected errors
      error_response = A2A::Protocol::JsonRpc.build_error_response(
        code: A2A::Protocol::JsonRpc::INTERNAL_ERROR,
        message: "Internal server error: #{e.message}",
        id: nil
      )
      error_response.to_json
    end
  end

  ##
  # Handle a single JSON-RPC request
  #
  # @param request [A2A::Protocol::Request] The parsed request
  # @param context [A2A::Server::Context, nil] Optional request context
  # @return [String] The JSON-RPC response as a string
  def handle_single_request(request, context: nil)
    # Apply middleware stack
    response = apply_middleware_stack(request, context) do
      # Route the request to the agent
      route_request(request, context: context)
    end

    # Convert response to JSON
    if response
      response.to_json
    else
      # No response for notifications
      nil
    end
  end

  ##
  # Handle a batch JSON-RPC request
  #
  # @param requests [Array<A2A::Protocol::Request>] Array of parsed requests
  # @param context [A2A::Server::Context, nil] Optional request context
  # @return [String] The JSON-RPC batch response as a string
  def handle_batch_request(requests, context: nil)
    # Process each request in the batch
    responses = requests.map do |request|
      # Apply middleware stack for each request
      apply_middleware_stack(request, context) do
        route_request(request, context: context)
      end
    rescue StandardError => e
      # Convert errors to error responses
      A2A::Errors::ErrorUtils.exception_to_json_rpc_error(e, request_id: request.id)
    end

    # Filter out nil responses (from notifications)
    batch_response = A2A::Protocol::JsonRpc.build_batch_response(responses.compact)

    # Return empty array if no responses (all notifications)
    batch_response.to_json
  end

  ##
  # Route a request to the appropriate agent method
  #
  # @param request [A2A::Protocol::Request] The JSON-RPC request
  # @param context [A2A::Server::Context, nil] Optional request context
  # @return [Hash, nil] The JSON-RPC response hash or nil for notifications
  def route_request(request, context: nil)
    # Validate the request
    validate_request(request)

    # Create or enhance context
    request_context = context || A2A::Server::Context.new(request: request)
    request_context.instance_variable_set(:@request, request) if context

    # Check if the method exists
    unless @agent.class.a2a_method_registered?(request.method)
      raise A2A::Errors::MethodNotFound, "Method '#{request.method}' not found"
    end

    # Get method definition for validation
    @agent.class.a2a_method_definition(request.method)

    # Validate parameters against capability schema if available
    validate_method_parameters(request.method, request.params)

    # Delegate to the agent
    @agent.handle_a2a_request(request, context: request_context)
  end

  ##
  # Add middleware to the handler
  #
  # @param middleware [Object] Middleware instance that responds to #call
  def add_middleware(middleware)
    @middleware_stack << middleware
  end

  ##
  # Remove middleware from the handler
  #
  # @param middleware [Object] Middleware instance to remove
  def remove_middleware(middleware)
    @middleware_stack.delete(middleware)
  end

  ##
  # Get all registered methods from the agent
  #
  # @return [Array<String>] Array of method names
  def registered_methods
    @agent.class.a2a_method_registry.keys
  end

  ##
  # Check if a method is registered
  #
  # @param method_name [String] The method name to check
  # @return [Boolean] True if the method is registered
  def method_registered?(method_name)
    @agent.class.a2a_method_registered?(method_name)
  end

  ##
  # Get method definition
  #
  # @param method_name [String] The method name
  # @return [Hash, nil] The method definition or nil if not found
  def method_definition(method_name)
    @agent.class.a2a_method_definition(method_name)
  end

  ##
  # Get all capabilities from the agent
  #
  # @return [Array<A2A::Protocol::Capability>] Array of capabilities
  def capabilities
    @agent.class.a2a_capability_registry.all
  end

  ##
  # Find capability by method name
  #
  # @param method_name [String] The method name
  # @return [A2A::Protocol::Capability, nil] The capability or nil if not found
  def find_capability_by_method(method_name)
    @agent.class.a2a_capability_registry.find_by(method: method_name).first
  end

  private

  ##
  # Validate that the agent includes the Agent module
  def validate_agent!
    return if @agent.class.included_modules.include?(A2A::Server::Agent)

    raise ArgumentError, "Agent must include A2A::Server::Agent module"
  end

  ##
  # Validate a JSON-RPC request
  #
  # @param request [A2A::Protocol::Request] The request to validate
  # @raise [A2A::Errors::InvalidRequest] If the request is invalid
  def validate_request(request)
    raise A2A::Errors::InvalidRequest, "Invalid request object" unless request.is_a?(A2A::Protocol::Request)

    raise A2A::Errors::InvalidRequest, "Method name is required" if request.method.nil? || (respond_to?(:empty?) && empty?) || (is_a?(String) && strip.empty?)

    return if request.params.is_a?(Hash) || request.params.is_a?(Array)

    raise A2A::Errors::InvalidParams, "Parameters must be an object or array"
  end

  ##
  # Validate method parameters against capability schema
  #
  # @param method_name [String] The method name
  # @param params [Hash, Array] The method parameters
  # @raise [A2A::Errors::InvalidParams] If parameters are invalid
  def validate_method_parameters(method_name, params)
    capability = find_capability_by_method(method_name)
    return unless capability # Skip validation if no capability defined

    begin
      capability.validate_input(params)
    rescue ArgumentError => e
      raise A2A::Errors::InvalidParams, "Parameter validation failed: #{e.message}"
    end
  end

  ##
  # Apply the middleware stack to a request
  #
  # @param request [A2A::Protocol::Request] The request
  # @param context [A2A::Server::Context, nil] The request context
  # @yield Block to execute after middleware
  # @return [Object] The result from the block
  def apply_middleware_stack(request, context, &block)
    # Build the middleware chain from the outside in
    chain = block

    @middleware_stack.reverse_each do |middleware|
      current_chain = chain
      chain = lambda do
        if middleware.respond_to?(:call)
          middleware.call(request, context) { current_chain.call }
        else
          # Fallback for middleware that don't implement call
          current_chain.call
        end
      end
    end

    # Execute the chain
    chain.call
  end
end
