# frozen_string_literal: true

module A2A
  module Rails
    ##
    # Controller helpers for A2A Rails integration
    #
    # This module provides helper methods for Rails controllers to handle A2A requests,
    # generate agent cards, and integrate with Rails authentication systems.
    #
    # @example Basic usage
    #   class MyAgentController < ApplicationController
    #     include A2A::Rails::ControllerHelpers
    #     
    #     a2a_skill "greeting" do |skill|
    #       skill.description = "Greet users"
    #     end
    #     
    #     a2a_method "greet" do |params|
    #       { message: "Hello, #{params[:name]}!" }
    #     end
    #   end
    #
    module ControllerHelpers
      extend ActiveSupport::Concern

      included do
        # Include the A2A Server Agent functionality
        include A2A::Server::Agent

        # Set up before actions for A2A requests
        before_action :authenticate_a2a_request, if: :a2a_request?
        before_action :set_a2a_headers, if: :a2a_request?
        
        # Skip CSRF protection for A2A endpoints
        skip_before_action :verify_authenticity_token, if: :a2a_request?
        
        # Handle A2A-specific exceptions
        rescue_from A2A::Errors::A2AError, with: :handle_a2a_error
        rescue_from A2A::Errors::TaskNotFound, with: :handle_task_not_found
        rescue_from A2A::Errors::AuthenticationError, with: :handle_authentication_error
      end

      class_methods do
        ##
        # Configure A2A agent metadata for this controller
        #
        # @param options [Hash] Agent configuration options
        # @option options [String] :name Agent name (defaults to controller name)
        # @option options [String] :description Agent description
        # @option options [String] :version Agent version
        # @option options [Array<String>] :tags Agent tags
        # @option options [Hash] :metadata Additional metadata
        #
        # @example
        #   class ChatController < ApplicationController
        #     include A2A::Rails::ControllerHelpers
        #     
        #     a2a_agent name: "Chat Assistant",
        #               description: "A helpful chat assistant",
        #               version: "1.0.0",
        #               tags: ["chat", "assistant"]
        #   end
        #
        def a2a_agent(**options)
          @_a2a_agent_config = options
        end

        # Get the A2A agent configuration
        def a2a_agent_config
          @_a2a_agent_config ||= {}
        end

        ##
        # Define authentication requirements for A2A methods
        #
        # @param methods [Array<String>] Method names that require authentication
        # @param strategy [Symbol] Authentication strategy (:devise, :jwt, :api_key, :custom)
        # @param options [Hash] Strategy-specific options
        #
        # @example With Devise
        #   a2a_authenticate :devise, methods: ["secure_method"]
        #
        # @example With custom strategy
        #   a2a_authenticate :custom, methods: ["secure_method"] do |request|
        #     request.headers["X-API-Key"] == "secret"
        #   end
        #
        def a2a_authenticate(strategy = :devise, methods: [], **options, &block)
          @_a2a_auth_config = {
            strategy: strategy,
            methods: Array(methods),
            options: options,
            block: block
          }
        end

        # Get the A2A authentication configuration
        def a2a_auth_config
          @_a2a_auth_config ||= { strategy: :none, methods: [], options: {}, block: nil }
        end
      end

      ##
      # Handle A2A JSON-RPC requests
      #
      # This method processes incoming JSON-RPC requests and delegates them to
      # the appropriate A2A method handlers.
      #
      # @return [Hash] JSON-RPC response
      #
      def handle_a2a_rpc
        request_body = request.body.read
        
        begin
          json_rpc_request = A2A::Protocol::JsonRpc.parse_request(request_body)
          
          # Handle batch requests
          if json_rpc_request.is_a?(Array)
            responses = json_rpc_request.map { |req| handle_single_a2a_request(req) }
            render json: responses
          else
            response = handle_single_a2a_request(json_rpc_request)
            render json: response
          end
        rescue A2A::Errors::A2AError => e
          render json: build_a2a_error_response(e), status: :bad_request
        rescue StandardError => e
          error = A2A::Errors::InternalError.new(e.message)
          render json: build_a2a_error_response(error), status: :internal_server_error
        end
      end

      ##
      # Generate agent card for this controller
      #
      # @param authenticated [Boolean] Whether to generate an authenticated card
      # @return [A2A::Types::AgentCard] The generated agent card
      #
      def generate_agent_card(authenticated: false)
        config = self.class.a2a_agent_config
        
        # Build base agent card
        card_data = {
          name: config[:name] || controller_name.humanize,
          description: config[:description] || "A2A agent for #{controller_name}",
          version: config[:version] || "1.0.0",
          url: agent_card_url,
          preferred_transport: "JSONRPC",
          skills: collect_skills,
          capabilities: collect_capabilities_hash,
          default_input_modes: A2A.config.default_input_modes,
          default_output_modes: A2A.config.default_output_modes,
          additional_interfaces: build_additional_interfaces,
          security: build_security_config,
          provider: build_provider_info,
          protocol_version: A2A.config.protocol_version,
          supports_authenticated_extended_card: supports_authenticated_card?,
          documentation_url: documentation_url,
          metadata: build_agent_metadata(config)
        }

        # Add authenticated-specific information
        if authenticated && current_user_authenticated?
          card_data = enhance_authenticated_card(card_data)
        end

        A2A::Types::AgentCard.new(**card_data)
      end

      ##
      # Render agent card as JSON response
      #
      # @param authenticated [Boolean] Whether to render authenticated card
      # @param format [Symbol] Response format (:json, :jws)
      #
      def render_agent_card(authenticated: false, format: :json)
        begin
          card = generate_agent_card(authenticated: authenticated)
          
          case format
          when :json
            render json: card.to_h
          when :jws
            # TODO: Implement JWS signing
            render json: { error: "JWS format not yet implemented" }, status: :not_implemented
          else
            render json: card.to_h
          end
        rescue StandardError => e
          render json: { error: e.message }, status: :internal_server_error
        end
      end

      ##
      # Check if current request is an A2A request
      #
      # @return [Boolean] True if this is an A2A request
      #
      def a2a_request?
        request.path.start_with?(A2A.config.mount_path) ||
        request.headers["Content-Type"]&.include?("application/json-rpc") ||
        params[:controller] == "a2a/rails/a2a"
      end

      ##
      # Check if current user is authenticated for A2A requests
      #
      # This method integrates with various Rails authentication systems.
      #
      # @return [Boolean] True if user is authenticated
      #
      def current_user_authenticated?
        auth_config = self.class.a2a_auth_config
        
        case auth_config[:strategy]
        when :devise
          respond_to?(:current_user) && current_user.present?
        when :jwt
          jwt_authenticated?
        when :api_key
          api_key_authenticated?
        when :custom
          auth_config[:block]&.call(request) || false
        else
          true # No authentication required
        end
      end

      ##
      # Get current user information for authenticated cards
      #
      # @return [Hash] User information hash
      #
      def current_user_info
        if respond_to?(:current_user) && current_user.present?
          {
            id: current_user.id,
            email: current_user.email,
            name: current_user.name || current_user.email,
            roles: current_user_roles
          }
        else
          {}
        end
      end

      ##
      # Get current user permissions for authenticated cards
      #
      # @return [Array<String>] List of user permissions
      #
      def current_user_permissions
        if respond_to?(:current_user) && current_user.present?
          # Try common permission methods
          if current_user.respond_to?(:permissions)
            current_user.permissions
          elsif current_user.respond_to?(:roles)
            current_user.roles.map(&:name)
          else
            []
          end
        else
          []
        end
      end

      private

      def handle_single_a2a_request(json_rpc_request)
        # Check method-level authentication
        if method_requires_authentication?(json_rpc_request.method)
          unless current_user_authenticated?
            raise A2A::Errors::AuthenticationError, "Authentication required for method: #{json_rpc_request.method}"
          end
        end

        # Delegate to the A2A request handler from Server::Agent
        handle_a2a_request(json_rpc_request)
      rescue A2A::Errors::A2AError => e
        build_a2a_error_response(e, json_rpc_request.id)
      rescue StandardError => e
        error = A2A::Errors::InternalError.new(e.message)
        build_a2a_error_response(error, json_rpc_request.id)
      end

      def build_a2a_error_response(error, id = nil)
        A2A::Protocol::JsonRpc.build_response(
          error: error.to_json_rpc_error,
          id: id
        )
      end

      def method_requires_authentication?(method_name)
        auth_config = self.class.a2a_auth_config
        auth_config[:methods].include?(method_name.to_s)
      end

      def authenticate_a2a_request
        return unless A2A.config.authentication_required
        return if current_user_authenticated?
        
        raise A2A::Errors::AuthenticationError, "Authentication required"
      end

      def set_a2a_headers
        response.headers["X-A2A-Version"] = A2A::VERSION
        response.headers["X-A2A-Protocol-Version"] = A2A.config.protocol_version
        response.headers["Content-Type"] = "application/json"
      end

      def collect_skills
        capabilities = self.class._a2a_capabilities || []
        capabilities.map do |capability|
          {
            id: capability.name,
            name: capability.name.humanize,
            description: capability.description,
            tags: capability.tags || [],
            examples: capability.examples || [],
            input_modes: capability.input_modes || A2A.config.default_input_modes,
            output_modes: capability.output_modes || A2A.config.default_output_modes
          }
        end
      end

      def collect_capabilities_hash
        {
          streaming: A2A.config.streaming_enabled,
          push_notifications: A2A.config.push_notifications_enabled,
          state_transition_history: true,
          extensions: []
        }
      end

      def build_additional_interfaces
        interfaces = []
        
        # Add gRPC interface if available
        if defined?(A2A::Transport::Grpc)
          interfaces << {
            transport: "GRPC",
            url: grpc_endpoint_url
          }
        end
        
        # Add HTTP+JSON interface
        interfaces << {
          transport: "HTTP+JSON",
          url: http_json_endpoint_url
        }
        
        interfaces
      end

      def build_security_config
        auth_config = self.class.a2a_auth_config
        
        case auth_config[:strategy]
        when :jwt
          {
            security_schemes: {
              jwt_auth: {
                type: "http",
                scheme: "bearer",
                bearer_format: "JWT"
              }
            },
            security: [{ jwt_auth: [] }]
          }
        when :api_key
          {
            security_schemes: {
              api_key_auth: {
                type: "apiKey",
                in: "header",
                name: "X-API-Key"
              }
            },
            security: [{ api_key_auth: [] }]
          }
        else
          {}
        end
      end

      def build_provider_info
        {
          name: Rails.application.class.module_parent_name,
          version: Rails.application.config.version rescue "1.0.0",
          url: root_url
        }
      end

      def supports_authenticated_card?
        self.class.a2a_auth_config[:strategy] != :none
      end

      def enhance_authenticated_card(card_data)
        card_data.merge(
          authenticated_user: current_user_info,
          permissions: current_user_permissions,
          authentication_context: {
            strategy: self.class.a2a_auth_config[:strategy],
            authenticated_at: Time.now.iso8601
          }
        )
      end

      def build_agent_metadata(config)
        base_metadata = {
          controller: controller_name,
          action: action_name,
          rails_version: Rails.version,
          created_at: Time.now.iso8601
        }
        
        base_metadata.merge(config[:metadata] || {})
      end

      def current_user_roles
        if respond_to?(:current_user) && current_user.present?
          if current_user.respond_to?(:roles)
            current_user.roles.map(&:name)
          elsif current_user.respond_to?(:role)
            [current_user.role]
          else
            ["user"]
          end
        else
          []
        end
      end

      def jwt_authenticated?
        auth_header = request.headers["Authorization"]
        return false unless auth_header&.start_with?("Bearer ")
        
        token = auth_header.split(" ").last
        
        begin
          # Basic JWT validation - applications should override this
          JWT.decode(token, nil, false)
          true
        rescue JWT::DecodeError
          false
        end
      end

      def api_key_authenticated?
        api_key = request.headers["X-API-Key"] || params[:api_key]
        return false unless api_key.present?
        
        # Basic API key validation - applications should override this
        # In a real application, this would check against a database or configuration
        api_key.length >= 32 # Simple validation
      end

      # URL helpers for agent card generation
      def agent_card_url
        "#{request.base_url}#{A2A.config.mount_path}/agent-card"
      end

      def grpc_endpoint_url
        # Convert HTTP URL to gRPC URL (typically different port)
        base_url = request.base_url.gsub(/:\d+/, ":#{grpc_port}")
        "#{base_url}/a2a.grpc"
      end

      def http_json_endpoint_url
        "#{request.base_url}#{A2A.config.mount_path}/http"
      end

      def documentation_url
        "#{request.base_url}/docs/a2a"
      end

      def grpc_port
        # Default gRPC port - applications can override this
        Rails.env.production? ? 443 : 50051
      end

      # Exception handlers
      def handle_a2a_error(error)
        render json: build_a2a_error_response(error), status: :bad_request
      end

      def handle_task_not_found(error)
        render json: build_a2a_error_response(error), status: :not_found
      end

      def handle_authentication_error(error)
        render json: build_a2a_error_response(error), status: :unauthorized
      end
    end
  end
end