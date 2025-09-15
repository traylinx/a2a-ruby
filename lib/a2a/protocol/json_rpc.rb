# frozen_string_literal: true

require "json"

# Try to use Oj for faster JSON parsing if available
begin
  require "oj"
  JSON_PARSER = Oj
  JSON_PARSE_OPTIONS = { mode: :strict, symbol_keys: false }.freeze
  JSON_GENERATE_OPTIONS = { mode: :compat }.freeze
rescue LoadError
  JSON_PARSER = JSON
  JSON_PARSE_OPTIONS = {}.freeze
  JSON_GENERATE_OPTIONS = {}.freeze
end

module A2A
  module Protocol
    ##
    # JSON-RPC 2.0 implementation for A2A protocol
    #
    # This class provides parsing and building functionality for JSON-RPC 2.0 requests
    # and responses, including support for batch requests and proper error handling.
    # Optimized for performance with optional Oj JSON parser support.
    #
    # @see https://www.jsonrpc.org/specification JSON-RPC 2.0 Specification
    class JsonRpc
      # JSON-RPC 2.0 version string
      JSONRPC_VERSION = "2.0"

      # Standard JSON-RPC error codes
      PARSE_ERROR = -32_700
      INVALID_REQUEST = -32_600
      METHOD_NOT_FOUND = -32_601
      INVALID_PARAMS = -32_602
      INTERNAL_ERROR = -32_603

      # A2A-specific error codes
      TASK_NOT_FOUND = -32_001
      TASK_NOT_CANCELABLE = -32_002
      INVALID_TASK_STATE = -32_003
      AUTHENTICATION_REQUIRED = -32_004
      AUTHORIZATION_FAILED = -32_005
      RATE_LIMIT_EXCEEDED = -32_006
      AGENT_UNAVAILABLE = -32_007
      PROTOCOL_VERSION_MISMATCH = -32_008
      CAPABILITY_NOT_SUPPORTED = -32_009
      RESOURCE_EXHAUSTED = -32_010

      ##
      # Parse a JSON-RPC 2.0 request from JSON string
      #
      # @param json_string [String] The JSON string to parse
      # @return [Request, Array<Request>] Single request or array for batch requests
      # @raise [A2A::Errors::ParseError] If JSON is invalid
      # @raise [A2A::Errors::InvalidRequest] If request format is invalid
      def self.parse_request(json_string)
        # Performance optimization: early return for empty strings
        return nil if json_string.nil? || (respond_to?(:empty?) && empty?) || (is_a?(String) && strip.empty?)

        begin
          # Use optimized JSON parser if available
          parsed = JSON_PARSER.parse(json_string, **JSON_PARSE_OPTIONS)
        rescue JSON::ParserError, Oj::ParseError => e
          raise A2A::Errors::ParseError, "Invalid JSON: #{e.message}"
        end

        if parsed.is_a?(Array)
          # Batch request
          raise A2A::Errors::InvalidRequest, "Empty batch request" if parsed.empty?

          # Performance optimization: use map! for in-place modification
          parsed.map! { |req| parse_single_request(req) }
        else
          # Single request
          parse_single_request(parsed)
        end
      end

      ##
      # Build a JSON-RPC 2.0 response
      #
      # @param result [Object, nil] The result value (mutually exclusive with error)
      # @param error [Hash, nil] The error object (mutually exclusive with result)
      # @param id [String, Integer, nil] The request ID
      # @return [Hash] The response hash
      def self.build_response(id:, **kwargs)
        result_provided = kwargs.key?(:result)
        error_provided = kwargs.key?(:error)

        raise ArgumentError, "Cannot specify both result and error" if result_provided && error_provided
        raise ArgumentError, "Must specify either result or error" unless result_provided || error_provided

        response = {
          jsonrpc: JSONRPC_VERSION,
          id: id
        }

        if error_provided
          response[:error] = normalize_error(kwargs[:error])
        else
          response[:result] = kwargs[:result]
        end

        response
      end

      ##
      # Build a JSON-RPC 2.0 batch response
      #
      # @param responses [Array<Hash>] Array of individual responses
      # @return [Array<Hash>] The batch response array
      def self.build_batch_response(responses)
        # Filter out notification responses (id: nil)
        responses.reject { |resp| resp[:id].nil? }
      end

      ##
      # Build an error response
      #
      # @param code [Integer] The error code
      # @param message [String] The error message
      # @param data [Object, nil] Additional error data
      # @param id [String, Integer, nil] The request ID
      # @return [Hash] The error response hash
      def self.build_error_response(code:, message:, id:, data: nil)
        error = { code: code, message: message }
        error[:data] = data if data

        build_response(error: error, id: id)
      end

      ##
      # Check if a hash represents a valid JSON-RPC 2.0 request
      #
      # @param hash [Hash] The hash to validate
      # @return [Boolean] True if valid request format
      def self.valid_request?(hash)
        return false unless hash.is_a?(Hash)
        return false unless hash["jsonrpc"] == JSONRPC_VERSION
        return false unless hash["method"].is_a?(String)

        # id can be string, number, or null (for notifications)
        id = hash["id"]
        return false unless id.nil? || id.is_a?(String) || id.is_a?(Integer)

        # params is optional but must be object or array if present
        params = hash["params"]
        return false if params && !params.is_a?(Hash) && !params.is_a?(Array)

        true
      end

      private_class_method def self.parse_single_request(hash)
        raise A2A::Errors::InvalidRequest, "Invalid request format" unless valid_request?(hash)

        Request.new(
          jsonrpc: hash["jsonrpc"],
          method: hash["method"],
          params: hash["params"] || {},
          id: hash["id"]
        )
      end

      private_class_method def self.normalize_error(error)
        if error.is_a?(A2A::Errors::A2AError)
          error.to_json_rpc_error
        elsif error.is_a?(Hash)
          error
        else
          { code: INTERNAL_ERROR, message: error.to_s }
        end
      end
    end

    ##
    # Represents a JSON-RPC 2.0 request
    class Request
      attr_reader :jsonrpc, :method, :params, :id

      ##
      # Initialize a new request
      #
      # @param jsonrpc [String] The JSON-RPC version (should be "2.0")
      # @param method [String] The method name
      # @param params [Hash, Array] The method parameters
      # @param id [String, Integer, nil] The request ID (nil for notifications)
      def initialize(jsonrpc:, method:, params: {}, id: nil)
        @jsonrpc = jsonrpc
        @method = method
        @params = params
        @id = id
      end

      ##
      # Check if this is a notification (no response expected)
      #
      # @return [Boolean] True if this is a notification
      def notification?
        @id.nil?
      end

      ##
      # Convert to hash representation
      #
      # @return [Hash] The request as a hash
      def to_h
        hash = {
          jsonrpc: @jsonrpc,
          method: @method
        }

        hash[:params] = @params unless @params.empty?
        hash[:id] = @id unless @id.nil?

        hash
      end

      ##
      # Convert to JSON string
      #
      # @return [String] The request as JSON
      def to_json(*args)
        # Use optimized JSON generator if available
        if defined?(JSON_PARSER) && JSON_PARSER == Oj
          Oj.dump(to_h, **JSON_GENERATE_OPTIONS)
        else
          to_h.to_json(*args)
        end
      end
    end
  end
end
