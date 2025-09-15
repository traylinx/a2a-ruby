# frozen_string_literal: true

require_relative "../version"

##
# Configuration class for A2A clients
#
# Manages client behavior including transport preferences, streaming options,
# authentication settings, and operational parameters.
#
module A2A
  module Client
    class Config
      attr_accessor :streaming, :polling, :supported_transports, :use_client_preference,
                    :accepted_output_modes, :push_notification_configs, :timeout,
                    :retry_attempts, :retry_delay, :max_retry_delay, :backoff_multiplier,
                    :endpoint_url, :authentication, :headers, :user_agent

      ##
      # Initialize a new client configuration
      #
      # @param streaming [Boolean] Enable streaming responses (default: true)
      # @param polling [Boolean] Enable polling for task updates (default: false)
      # @param supported_transports [Array<String>] Supported transport protocols
      # @param use_client_preference [Boolean] Use client transport preference (default: true)
      # @param accepted_output_modes [Array<String>] Accepted output modes
      # @param push_notification_configs [Array<Hash>] Push notification configurations
      # @param timeout [Integer] Request timeout in seconds (default: 30)
      # @param retry_attempts [Integer] Number of retry attempts (default: 3)
      # @param retry_delay [Float] Initial retry delay in seconds (default: 1.0)
      # @param max_retry_delay [Float] Maximum retry delay in seconds (default: 60.0)
      # @param backoff_multiplier [Float] Backoff multiplier for retries (default: 2.0)
      # @param endpoint_url [String] Base endpoint URL
      # @param authentication [Hash] Authentication configuration
      # @param headers [Hash] Additional HTTP headers
      # @param user_agent [String] User agent string
      def initialize(streaming: true, polling: false, supported_transports: nil,
                     use_client_preference: true, accepted_output_modes: nil,
                     push_notification_configs: nil, timeout: 30, retry_attempts: 3,
                     retry_delay: 1.0, max_retry_delay: 60.0, backoff_multiplier: 2.0,
                     endpoint_url: nil, authentication: nil, headers: nil, user_agent: nil)
        @streaming = streaming
        @polling = polling
        @supported_transports = supported_transports || [A2A::Types::TRANSPORT_JSONRPC]
        @use_client_preference = use_client_preference
        @accepted_output_modes = accepted_output_modes || %w[text file data]
        @push_notification_configs = push_notification_configs || []
        @timeout = timeout
        @retry_attempts = retry_attempts
        @retry_delay = retry_delay
        @max_retry_delay = max_retry_delay
        @backoff_multiplier = backoff_multiplier
        @endpoint_url = endpoint_url
        @authentication = authentication || {}
        @headers = headers || {}
        @user_agent = user_agent || "a2a-ruby/#{A2A::VERSION}"

        validate!
      end

      ##
      # Check if streaming is enabled
      #
      # @return [Boolean] True if streaming is enabled
      def streaming?
        @streaming
      end

      ##
      # Check if polling is enabled
      #
      # @return [Boolean] True if polling is enabled
      def polling?
        @polling
      end

      ##
      # Check if client preference should be used for transport negotiation
      #
      # @return [Boolean] True if client preference should be used
      def use_client_preference?
        @use_client_preference
      end

      ##
      # Get the preferred transport protocol
      #
      # @return [String] The preferred transport protocol
      def preferred_transport
        @supported_transports.first
      end

      ##
      # Check if a transport is supported
      #
      # @param transport [String] The transport to check
      # @return [Boolean] True if the transport is supported
      def supports_transport?(transport)
        @supported_transports.include?(transport)
      end

      ##
      # Add a supported transport
      #
      # @param transport [String] The transport to add
      def add_transport(transport)
        @supported_transports << transport unless @supported_transports.include?(transport)
      end

      ##
      # Remove a supported transport
      #
      # @param transport [String] The transport to remove
      def remove_transport(transport)
        @supported_transports.delete(transport)
      end

      ##
      # Get authentication configuration for a specific type
      #
      # @param type [String] The authentication type
      # @return [Hash, nil] The authentication configuration
      def auth_config(type)
        @authentication[type]
      end

      ##
      # Set authentication configuration
      #
      # @param type [String] The authentication type
      # @param config [Hash] The authentication configuration
      def set_auth_config(type, config)
        @authentication[type] = config
      end

      ##
      # Get all HTTP headers including authentication headers
      #
      # @return [Hash] All HTTP headers
      def all_headers
        auth_headers = build_auth_headers
        @headers.merge(auth_headers)
      end

      ##
      # Create a copy of the configuration
      #
      # @return [Config] A new configuration instance
      def dup
        self.class.new(
          streaming: @streaming,
          polling: @polling,
          supported_transports: @supported_transports.dup,
          use_client_preference: @use_client_preference,
          accepted_output_modes: @accepted_output_modes.dup,
          push_notification_configs: @push_notification_configs.dup,
          timeout: @timeout,
          retry_attempts: @retry_attempts,
          retry_delay: @retry_delay,
          max_retry_delay: @max_retry_delay,
          backoff_multiplier: @backoff_multiplier,
          endpoint_url: @endpoint_url,
          authentication: @authentication.dup,
          headers: @headers.dup,
          user_agent: @user_agent
        )
      end

      private

      def validate!
        raise ArgumentError, "timeout must be positive" if @timeout <= 0
        raise ArgumentError, "retry_attempts must be non-negative" if @retry_attempts.negative?
        raise ArgumentError, "retry_delay must be positive" if @retry_delay <= 0
        raise ArgumentError, "max_retry_delay must be positive" if @max_retry_delay <= 0
        raise ArgumentError, "backoff_multiplier must be positive" if @backoff_multiplier <= 0

        @supported_transports.each do |transport|
          raise ArgumentError, "unsupported transport: #{transport}" unless A2A::Types::VALID_TRANSPORTS.include?(transport)
        end
      end

      def build_auth_headers
        headers = {}

        # Add API key authentication
        if (api_key_config = @authentication["api_key"])
          case api_key_config["in"]
          when "header"
            headers[api_key_config["name"]] = api_key_config["value"]
          end
        end

        # Add bearer token authentication
        if (bearer_config = @authentication["bearer"])
          headers["Authorization"] = "Bearer #{bearer_config['token']}"
        end

        # Add basic authentication
        if (basic_config = @authentication["basic"])
          require "base64"
          credentials = Base64.strict_encode64("#{basic_config['username']}:#{basic_config['password']}")
          headers["Authorization"] = "Basic #{credentials}"
        end

        headers
      end
    end
  end
end
