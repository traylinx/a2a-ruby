# frozen_string_literal: true

##
# Exception classes for the A2A Ruby SDK
#
module A2A
  module Errors
    ##
    # Base class for all A2A errors
    #
    class A2AError < StandardError
      attr_reader :code, :data

      def initialize(message = nil, code: nil, data: nil)
        super(message)
        @code = code
        @data = data
      end

      # Convert to JSON-RPC error format
      # @return [Hash]
      def to_json_rpc_error
        {
          code: @code,
          message: message,
          data: @data
        }.compact
      end
    end

    ##
    # Configuration-related errors
    #
    class ConfigurationError < A2AError; end

    ##
    # JSON-RPC 2.0 standard errors
    #

    # Parse error - Invalid JSON was received by the server
    class ParseError < A2AError
      def initialize(message = "Parse error", **options)
        super(message, code: -32_700, **options)
      end
    end

    # Invalid Request - The JSON sent is not a valid Request object
    class InvalidRequest < A2AError
      def initialize(message = "Invalid Request", **options)
        super(message, code: -32_600, **options)
      end
    end

    # Method not found - The method does not exist / is not available
    class MethodNotFound < A2AError
      def initialize(message = "Method not found", **options)
        super(message, code: -32_601, **options)
      end
    end

    # Invalid params - Invalid method parameter(s)
    class InvalidParams < A2AError
      def initialize(message = "Invalid params", **options)
        super(message, code: -32_602, **options)
      end
    end

    # Internal error - Internal JSON-RPC error
    class InternalError < A2AError
      def initialize(message = "Internal error", **options)
        super(message, code: -32_603, **options)
      end
    end

    ##
    # A2A-specific errors (-32001 to -32010)
    #

    # Task not found
    class TaskNotFound < A2AError
      def initialize(message = "Task not found", **options)
        super(message, code: -32_001, **options)
      end
    end

    # Task cannot be canceled
    class TaskNotCancelable < A2AError
      def initialize(message = "Task cannot be canceled", **options)
        super(message, code: -32_002, **options)
      end
    end

    # Invalid task state
    class InvalidTaskState < A2AError
      def initialize(message = "Invalid task state", **options)
        super(message, code: -32_003, **options)
      end
    end

    # Authentication required
    class AuthenticationRequired < A2AError
      def initialize(message = "Authentication required", **options)
        super(message, code: -32_004, **options)
      end
    end

    # Authorization failed
    class AuthorizationFailed < A2AError
      def initialize(message = "Authorization failed", **options)
        super(message, code: -32_005, **options)
      end
    end

    # Rate limit exceeded
    class RateLimitExceeded < A2AError
      def initialize(message = "Rate limit exceeded", **options)
        super(message, code: -32_006, **options)
      end
    end

    # Agent unavailable
    class AgentUnavailable < A2AError
      def initialize(message = "Agent unavailable", **options)
        super(message, code: -32_007, **options)
      end
    end

    # Protocol version mismatch
    class ProtocolVersionMismatch < A2AError
      def initialize(message = "Protocol version mismatch", **options)
        super(message, code: -32_008, **options)
      end
    end

    # Capability not supported
    class CapabilityNotSupported < A2AError
      def initialize(message = "Capability not supported", **options)
        super(message, code: -32_009, **options)
      end
    end

    # Resource exhausted
    class ResourceExhausted < A2AError
      def initialize(message = "Resource exhausted", **options)
        super(message, code: -32_010, **options)
      end
    end

    # Not found (generic)
    class NotFound < A2AError
      def initialize(message = "Not found", **options)
        super(message, code: -32_404, **options)
      end
    end

    ##
    # Client-side errors
    #

    # Base client error
    class ClientError < A2AError; end

    # HTTP-related errors
    class HTTPError < ClientError
      attr_reader :status_code, :response_body

      def initialize(message, status_code: nil, response_body: nil, **options)
        super(message, **options)
        @status_code = status_code
        @response_body = response_body
      end
    end

    # Timeout errors
    class TimeoutError < ClientError; end

    # Authentication errors
    class AuthenticationError < ClientError; end

    # JSON parsing errors
    class JSONError < ClientError; end

    # Transport errors
    class TransportError < ClientError; end

    # Server-side errors
    class ServerError < A2AError
      attr_reader :error

      def initialize(error = nil, message: nil)
        @error = error
        super(message || error&.message || "Server error")
      end
    end

    ##
    # Utility methods for error handling
    #
    module ErrorUtils
      ##
      # Convert an exception to a JSON-RPC error response
      #
      # @param exception [Exception] The exception to convert
      # @param request_id [String, Integer, nil] The request ID
      # @return [Hash] JSON-RPC error response
      def self.exception_to_json_rpc_error(exception, request_id: nil)
        if exception.is_a?(A2AError)
          A2A::Protocol::JsonRpc.build_error_response(
            code: exception.code,
            message: exception.message,
            data: exception.data,
            id: request_id
          )
        else
          # Map standard Ruby exceptions to JSON-RPC errors
          case exception
          when ArgumentError
            A2A::Protocol::JsonRpc.build_error_response(
              code: A2A::Protocol::JsonRpc::INVALID_PARAMS,
              message: exception.message,
              id: request_id
            )
          when NoMethodError
            A2A::Protocol::JsonRpc.build_error_response(
              code: A2A::Protocol::JsonRpc::METHOD_NOT_FOUND,
              message: "Method not found",
              id: request_id
            )
          else
            A2A::Protocol::JsonRpc.build_error_response(
              code: A2A::Protocol::JsonRpc::INTERNAL_ERROR,
              message: exception.message,
              id: request_id
            )
          end
        end
      end

      ##
      # Create an A2A error from a JSON-RPC error code
      #
      # @param code [Integer] The error code
      # @param message [String] The error message
      # @param data [Object, nil] Additional error data
      # @return [A2AError] The appropriate error instance
      def self.from_json_rpc_code(code, message, data: nil)
        case code
        when A2A::Protocol::JsonRpc::PARSE_ERROR
          ParseError.new(message, data: data)
        when A2A::Protocol::JsonRpc::INVALID_REQUEST
          InvalidRequest.new(message, data: data)
        when A2A::Protocol::JsonRpc::METHOD_NOT_FOUND
          MethodNotFound.new(message, data: data)
        when A2A::Protocol::JsonRpc::INVALID_PARAMS
          InvalidParams.new(message, data: data)
        when A2A::Protocol::JsonRpc::INTERNAL_ERROR
          InternalError.new(message, data: data)
        when A2A::Protocol::JsonRpc::TASK_NOT_FOUND
          TaskNotFound.new(message, data: data)
        when A2A::Protocol::JsonRpc::TASK_NOT_CANCELABLE
          TaskNotCancelable.new(message, data: data)
        when A2A::Protocol::JsonRpc::INVALID_TASK_STATE
          InvalidTaskState.new(message, data: data)
        when A2A::Protocol::JsonRpc::AUTHENTICATION_REQUIRED
          AuthenticationRequired.new(message, data: data)
        when A2A::Protocol::JsonRpc::AUTHORIZATION_FAILED
          AuthorizationFailed.new(message, data: data)
        when A2A::Protocol::JsonRpc::RATE_LIMIT_EXCEEDED
          RateLimitExceeded.new(message, data: data)
        when A2A::Protocol::JsonRpc::AGENT_UNAVAILABLE
          AgentUnavailable.new(message, data: data)
        when A2A::Protocol::JsonRpc::PROTOCOL_VERSION_MISMATCH
          ProtocolVersionMismatch.new(message, data: data)
        when A2A::Protocol::JsonRpc::CAPABILITY_NOT_SUPPORTED
          CapabilityNotSupported.new(message, data: data)
        when A2A::Protocol::JsonRpc::RESOURCE_EXHAUSTED
          ResourceExhausted.new(message, data: data)
        else
          A2AError.new(message, code: code, data: data)
        end
      end
    end
  end
end
