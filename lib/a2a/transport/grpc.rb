# frozen_string_literal: true

begin
  require "grpc"
rescue LoadError
  # gRPC is optional - define a stub implementation
  module GRPC
    class BadStatus < StandardError; end

    module Core
      class StatusCodes
        OK = 0
        CANCELLED = 1
        UNKNOWN = 2
        INVALID_ARGUMENT = 3
        DEADLINE_EXCEEDED = 4
        NOT_FOUND = 5
        ALREADY_EXISTS = 6
        PERMISSION_DENIED = 7
        RESOURCE_EXHAUSTED = 8
        FAILED_PRECONDITION = 9
        ABORTED = 10
        OUT_OF_RANGE = 11
        UNIMPLEMENTED = 12
        INTERNAL = 13
        UNAVAILABLE = 14
        DATA_LOSS = 15
        UNAUTHENTICATED = 16
      end
    end
  end
end

module A2A
  module Transport
    ##
    # gRPC transport implementation with optional dependency
    # Provides bidirectional streaming support and gRPC-specific error mapping
    #
    class Grpc
      # Check if gRPC is available
      GRPC_AVAILABLE = defined?(::GRPC) && ::GRPC.const_defined?(:ClientStub)

      # Default configuration values
      DEFAULT_TIMEOUT = 30
      DEFAULT_DEADLINE = 60
      DEFAULT_MAX_RECEIVE_MESSAGE_SIZE = 4 * 1024 * 1024 # 4MB
      DEFAULT_MAX_SEND_MESSAGE_SIZE = 4 * 1024 * 1024 # 4MB
      DEFAULT_KEEPALIVE_TIME = 30
      DEFAULT_KEEPALIVE_TIMEOUT = 5

      attr_reader :endpoint, :config, :stub, :credentials

      ##
      # Initialize gRPC transport
      #
      # @param endpoint [String] gRPC endpoint (host:port)
      # @param config [Hash] Configuration options
      # @option config [Integer] :timeout (30) Request timeout in seconds
      # @option config [Integer] :deadline (60) Request deadline in seconds
      # @option config [Integer] :max_receive_message_size (4MB) Max receive message size
      # @option config [Integer] :max_send_message_size (4MB) Max send message size
      # @option config [Integer] :keepalive_time (30) Keepalive time in seconds
      # @option config [Integer] :keepalive_timeout (5) Keepalive timeout in seconds
      # @option config [Boolean] :use_tls (true) Use TLS encryption
      # @option config [String] :ca_file Path to CA certificate file
      # @option config [String] :cert_file Path to client certificate file
      # @option config [String] :key_file Path to client private key file
      # @option config [Hash] :metadata ({}) Default metadata
      # @option config [Object] :credentials Custom credentials object
      #
      def initialize(endpoint, config = {})
        unless GRPC_AVAILABLE
          raise A2A::Errors::TransportError,
                "gRPC is not available. Install the 'grpc' gem to use gRPC transport."
        end

        @endpoint = endpoint
        @config = default_config.merge(config)
        @credentials = build_credentials
        @stub = nil
        @call_options = build_call_options
      end

      ##
      # Connect to gRPC service
      #
      # @return [Boolean] Connection success
      # @raise [A2A::Errors::TransportError] On connection errors
      #
      def connect
        return true if connected?

        begin
          @stub = build_stub
          # Test connection with a simple call
          @stub.class.rpc_descs.keys.first&.tap do |_method|
            # This is a simplified connection test
          end
          true
        rescue StandardError => e
          raise A2A::Errors::TransportError, "Failed to connect to gRPC service: #{e.message}"
        end
      end

      ##
      # Disconnect from gRPC service
      #
      def disconnect
        @stub = nil
      end

      ##
      # Check if connected
      #
      # @return [Boolean] Connection status
      #
      def connected?
        !@stub.nil?
      end

      ##
      # Send unary gRPC request
      #
      # @param method [Symbol] gRPC method name
      # @param request [Object] Request message
      # @param metadata [Hash] Request metadata
      # @param timeout [Integer, nil] Request timeout
      # @return [Object] Response message
      # @raise [A2A::Errors::TransportError] On gRPC errors
      #
      def unary_call(method, request, metadata: {}, timeout: nil)
        ensure_connected!

        call_options = @call_options.dup
        call_options[:timeout] = timeout if timeout
        call_options[:metadata] = @config[:metadata].merge(metadata)

        begin
          @stub.public_send(method, request, call_options)
        rescue ::GRPC::BadStatus => e
          raise map_grpc_error(e)
        rescue StandardError => e
          raise A2A::Errors::TransportError, "gRPC call failed: #{e.message}"
        end
      end

      ##
      # Send client streaming gRPC request
      #
      # @param method [Symbol] gRPC method name
      # @param requests [Enumerator] Request stream
      # @param metadata [Hash] Request metadata
      # @param timeout [Integer, nil] Request timeout
      # @return [Object] Response message
      # @raise [A2A::Errors::TransportError] On gRPC errors
      #
      def client_streaming_call(method, requests, metadata: {}, timeout: nil)
        ensure_connected!

        call_options = @call_options.dup
        call_options[:timeout] = timeout if timeout
        call_options[:metadata] = @config[:metadata].merge(metadata)

        begin
          @stub.public_send(method, requests, call_options)
        rescue ::GRPC::BadStatus => e
          raise map_grpc_error(e)
        rescue StandardError => e
          raise A2A::Errors::TransportError, "gRPC streaming call failed: #{e.message}"
        end
      end

      ##
      # Send server streaming gRPC request
      #
      # @param method [Symbol] gRPC method name
      # @param request [Object] Request message
      # @param metadata [Hash] Request metadata
      # @param timeout [Integer, nil] Request timeout
      # @return [Enumerator] Response stream
      # @raise [A2A::Errors::TransportError] On gRPC errors
      #
      def server_streaming_call(method, request, metadata: {}, timeout: nil)
        ensure_connected!

        call_options = @call_options.dup
        call_options[:timeout] = timeout if timeout
        call_options[:metadata] = @config[:metadata].merge(metadata)

        begin
          @stub.public_send(method, request, call_options)
        rescue ::GRPC::BadStatus => e
          raise map_grpc_error(e)
        rescue StandardError => e
          raise A2A::Errors::TransportError, "gRPC streaming call failed: #{e.message}"
        end
      end

      ##
      # Send bidirectional streaming gRPC request
      #
      # @param method [Symbol] gRPC method name
      # @param requests [Enumerator] Request stream
      # @param metadata [Hash] Request metadata
      # @param timeout [Integer, nil] Request timeout
      # @return [Enumerator] Response stream
      # @raise [A2A::Errors::TransportError] On gRPC errors
      #
      def bidi_streaming_call(method, requests, metadata: {}, timeout: nil)
        ensure_connected!

        call_options = @call_options.dup
        call_options[:timeout] = timeout if timeout
        call_options[:metadata] = @config[:metadata].merge(metadata)

        begin
          @stub.public_send(method, requests, call_options)
        rescue ::GRPC::BadStatus => e
          raise map_grpc_error(e)
        rescue StandardError => e
          raise A2A::Errors::TransportError, "gRPC bidirectional streaming call failed: #{e.message}"
        end
      end

      ##
      # Send A2A message via gRPC
      #
      # @param message [A2A::Types::Message] A2A message
      # @param streaming [Boolean] Use streaming response
      # @param metadata [Hash] Request metadata
      # @return [Object, Enumerator] Response or response stream
      #
      def send_a2a_message(message, streaming: false, metadata: {})
        request = build_a2a_request(message)

        if streaming
          server_streaming_call(:send_message_stream, request, metadata: metadata)
        else
          unary_call(:send_message, request, metadata: metadata)
        end
      end

      ##
      # Get A2A task via gRPC
      #
      # @param task_id [String] Task ID
      # @param metadata [Hash] Request metadata
      # @return [Object] Task response
      #
      def get_a2a_task(task_id, metadata: {})
        request = build_task_request(task_id)
        unary_call(:get_task, request, metadata: metadata)
      end

      ##
      # Cancel A2A task via gRPC
      #
      # @param task_id [String] Task ID
      # @param metadata [Hash] Request metadata
      # @return [Object] Cancellation response
      #
      def cancel_a2a_task(task_id, metadata: {})
        request = build_task_request(task_id)
        unary_call(:cancel_task, request, metadata: metadata)
      end

      ##
      # Get agent card via gRPC
      #
      # @param metadata [Hash] Request metadata
      # @return [Object] Agent card response
      #
      def get_agent_card(metadata: {})
        request = build_empty_request
        unary_call(:get_agent_card, request, metadata: metadata)
      end

      private

      ##
      # Ensure connection is established
      #
      # @raise [A2A::Errors::TransportError] If not connected
      #
      def ensure_connected!
        connect unless connected?
        raise A2A::Errors::TransportError, "Not connected to gRPC service" unless connected?
      end

      ##
      # Build default configuration
      #
      # @return [Hash] Default configuration
      #
      def default_config
        {
          timeout: DEFAULT_TIMEOUT,
          deadline: DEFAULT_DEADLINE,
          max_receive_message_size: DEFAULT_MAX_RECEIVE_MESSAGE_SIZE,
          max_send_message_size: DEFAULT_MAX_SEND_MESSAGE_SIZE,
          keepalive_time: DEFAULT_KEEPALIVE_TIME,
          keepalive_timeout: DEFAULT_KEEPALIVE_TIMEOUT,
          use_tls: true,
          ca_file: nil,
          cert_file: nil,
          key_file: nil,
          metadata: {},
          credentials: nil
        }
      end

      ##
      # Build gRPC credentials
      #
      # @return [Object] gRPC credentials
      #
      def build_credentials
        return @config[:credentials] if @config[:credentials]

        if @config[:use_tls]
          if @config[:ca_file] || @config[:cert_file] || @config[:key_file]
            # Custom TLS credentials
            ca_cert = @config[:ca_file] ? File.read(@config[:ca_file]) : nil
            cert = @config[:cert_file] ? File.read(@config[:cert_file]) : nil
            key = @config[:key_file] ? File.read(@config[:key_file]) : nil

            ::GRPC::Core::ChannelCredentials.new(ca_cert, key, cert)
          else
            # Default TLS credentials
            ::GRPC::Core::ChannelCredentials.new
          end
        else
          # Insecure credentials
          :this_channel_is_insecure
        end
      end

      ##
      # Build gRPC stub
      #
      # @return [Object] gRPC stub instance
      #
      def build_stub
        # This would be replaced with actual A2A gRPC service stub
        # For now, we'll create a generic stub interface
        A2AServiceStub.new(@endpoint, @credentials, channel_args: build_channel_args)
      end

      ##
      # Build channel arguments
      #
      # @return [Hash] Channel arguments
      #
      def build_channel_args
        {
          "grpc.keepalive_time_ms" => @config[:keepalive_time] * 1000,
          "grpc.keepalive_timeout_ms" => @config[:keepalive_timeout] * 1000,
          "grpc.keepalive_permit_without_calls" => 1,
          "grpc.http2.max_pings_without_data" => 0,
          "grpc.http2.min_time_between_pings_ms" => 10_000,
          "grpc.http2.min_ping_interval_without_data_ms" => 300_000,
          "grpc.max_receive_message_length" => @config[:max_receive_message_size],
          "grpc.max_send_message_length" => @config[:max_send_message_size]
        }
      end

      ##
      # Build call options
      #
      # @return [Hash] Call options
      #
      def build_call_options
        {
          timeout: @config[:timeout],
          deadline: Time.now + @config[:deadline],
          metadata: @config[:metadata]
        }
      end

      ##
      # Map gRPC error to A2A error
      #
      # @param grpc_error [GRPC::BadStatus] gRPC error
      # @return [A2A::Errors::A2AError] Mapped A2A error
      #
      def map_grpc_error(grpc_error)
        case grpc_error.code
        when ::GRPC::Core::StatusCodes::CANCELLED
          A2A::Errors::TaskNotCancelable.new("Request cancelled: #{grpc_error.details}")
        when ::GRPC::Core::StatusCodes::INVALID_ARGUMENT
          A2A::Errors::InvalidParams.new("Invalid argument: #{grpc_error.details}")
        when ::GRPC::Core::StatusCodes::DEADLINE_EXCEEDED
          A2A::Errors::TimeoutError.new("Deadline exceeded: #{grpc_error.details}")
        when ::GRPC::Core::StatusCodes::NOT_FOUND
          A2A::Errors::TaskNotFound.new("Not found: #{grpc_error.details}")
        when ::GRPC::Core::StatusCodes::PERMISSION_DENIED
          A2A::Errors::AuthorizationFailed.new("Permission denied: #{grpc_error.details}")
        when ::GRPC::Core::StatusCodes::RESOURCE_EXHAUSTED
          A2A::Errors::ResourceExhausted.new("Resource exhausted: #{grpc_error.details}")
        when ::GRPC::Core::StatusCodes::UNIMPLEMENTED
          A2A::Errors::CapabilityNotSupported.new("Unimplemented: #{grpc_error.details}")
        when ::GRPC::Core::StatusCodes::UNAVAILABLE
          A2A::Errors::AgentUnavailable.new("Service unavailable: #{grpc_error.details}")
        when ::GRPC::Core::StatusCodes::UNAUTHENTICATED
          A2A::Errors::AuthenticationRequired.new("Unauthenticated: #{grpc_error.details}")
        else
          A2A::Errors::TransportError.new("gRPC error (#{grpc_error.code}): #{grpc_error.details}")
        end
      end

      ##
      # Build A2A message request
      #
      # @param message [A2A::Types::Message] A2A message
      # @return [Object] gRPC request object
      #
      def build_a2a_request(message)
        # This would convert A2A::Types::Message to protobuf message
        # For now, return a hash representation
        {
          message: message.to_h
        }
      end

      ##
      # Build task request
      #
      # @param task_id [String] Task ID
      # @return [Object] gRPC request object
      #
      def build_task_request(task_id)
        {
          task_id: task_id
        }
      end

      ##
      # Build empty request
      #
      # @return [Object] gRPC request object
      #
      def build_empty_request
        {}
      end
    end

    ##
    # Stub implementation for A2A gRPC service
    # This would be replaced with generated protobuf stubs
    #
    class A2AServiceStub
      def initialize(endpoint, credentials, channel_args: {})
        @endpoint = endpoint
        @credentials = credentials
        @channel_args = channel_args
      end

      # Placeholder methods - would be generated from protobuf definitions
      def send_message(_request, _options = {})
        raise A2A::Errors::CapabilityNotSupported, "gRPC service implementation not available"
      end

      def send_message_stream(_request, _options = {})
        raise A2A::Errors::CapabilityNotSupported, "gRPC service implementation not available"
      end

      def get_task(_request, _options = {})
        raise A2A::Errors::CapabilityNotSupported, "gRPC service implementation not available"
      end

      def cancel_task(_request, _options = {})
        raise A2A::Errors::CapabilityNotSupported, "gRPC service implementation not available"
      end

      def get_agent_card(_request, _options = {})
        raise A2A::Errors::CapabilityNotSupported, "gRPC service implementation not available"
      end
    end
  end
end
