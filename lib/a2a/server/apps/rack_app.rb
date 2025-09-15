# frozen_string_literal: true

require "json"
require "rack"
require_relative "../request_handler"
require_relative "../../protocol/json_rpc"

module A2A
  module Server
    module Apps
      ##
      # Rack application for serving A2A protocol endpoints
      #
      # This class provides a Rack-compatible application that can handle
      # A2A JSON-RPC requests and serve agent cards. It's similar to the
      # Python FastAPI implementation but uses Rack for Ruby web servers.
      #
      class RackApp
        AGENT_CARD_PATH = "/.well-known/a2a/agent-card"
        EXTENDED_AGENT_CARD_PATH = "/a2a/agent-card/extended"
        RPC_PATH = "/a2a/rpc"

        attr_reader :agent_card, :request_handler, :extended_agent_card

        ##
        # Initialize the Rack application
        #
        # @param agent_card [A2A::Types::AgentCard] The agent card describing capabilities
        # @param request_handler [RequestHandler] The request handler for processing A2A requests
        # @param extended_agent_card [A2A::Types::AgentCard, nil] Optional extended agent card
        # @param card_modifier [Proc, nil] Optional callback to modify the public agent card
        # @param extended_card_modifier [Proc, nil] Optional callback to modify the extended agent card
        def initialize(agent_card:, request_handler:, extended_agent_card: nil, card_modifier: nil, extended_card_modifier: nil)
          @agent_card = agent_card
          @request_handler = request_handler
          @extended_agent_card = extended_agent_card
          @card_modifier = card_modifier
          @extended_card_modifier = extended_card_modifier
        end

        ##
        # Rack application call method
        #
        # @param env [Hash] Rack environment
        # @return [Array] Rack response [status, headers, body]
        def call(env)
          request = Rack::Request.new(env)

          case request.path_info
          when AGENT_CARD_PATH
            handle_agent_card(request)
          when EXTENDED_AGENT_CARD_PATH
            handle_extended_agent_card(request)
          when RPC_PATH
            handle_rpc_request(request)
          else
            not_found_response
          end
        rescue StandardError => e
          error_response(500, "Internal Server Error: #{e.message}")
        end

        private

        ##
        # Handle agent card requests
        #
        # @param request [Rack::Request] The request object
        # @return [Array] Rack response
        def handle_agent_card(request)
          return method_not_allowed_response unless request.get?

          card_to_serve = @agent_card
          card_to_serve = @card_modifier.call(card_to_serve) if @card_modifier

          json_response(200, card_to_serve.to_h)
        end

        ##
        # Handle extended agent card requests
        #
        # @param request [Rack::Request] The request object
        # @return [Array] Rack response
        def handle_extended_agent_card(request)
          return method_not_allowed_response unless request.get?

          return error_response(404, "Extended agent card not supported") unless @agent_card.supports_authenticated_extended_card

          # Build server context from request
          context = build_server_context(request)

          card_to_serve = @extended_agent_card || @agent_card

          card_to_serve = @extended_card_modifier.call(card_to_serve, context) if @extended_card_modifier

          json_response(200, card_to_serve.to_h)
        end

        ##
        # Handle JSON-RPC requests
        #
        # @param request [Rack::Request] The request object
        # @return [Array] Rack response
        def handle_rpc_request(request)
          return method_not_allowed_response unless request.post?

          # Check content type
          content_type = request.content_type
          return error_response(400, "Content-Type must be application/json") unless content_type&.include?("application/json")

          # Parse request body
          body = request.body.read
          request.body.rewind

          # Parse JSON-RPC request directly from string
          begin
            rpc_request = A2A::Protocol::JsonRpc.parse_request(body)
          rescue A2A::Errors::A2AError => e
            return json_rpc_error_response(
              nil, # No ID available if parsing failed
              e.code,
              e.message,
              e.data
            )
          end

          # Build server context
          context = build_server_context(request)

          # Route to appropriate handler method
          begin
            result = route_request(rpc_request, context)

            # Handle streaming responses
            return streaming_response(result) if result.is_a?(Enumerator)

            # Return regular JSON-RPC response
            response_data = A2A::Protocol::JsonRpc.build_response(
              result: result,
              id: rpc_request.id
            )
            json_response(200, response_data)
          rescue A2A::Errors::A2AError => e
            json_rpc_error_response(rpc_request.id, e.code, e.message, e.data)
          rescue StandardError => e
            json_rpc_error_response(
              rpc_request.id,
              A2A::Protocol::JsonRpc::INTERNAL_ERROR,
              "Internal error: #{e.message}"
            )
          end
        end

        ##
        # Route JSON-RPC request to appropriate handler method
        #
        # @param request [A2A::Protocol::Request] The parsed JSON-RPC request
        # @param context [A2A::Server::Context] The server context
        # @return [Object] The result from the handler
        def route_request(request, context)
          case request.method
          when "message/send"
            @request_handler.on_message_send(request.params, context)
          when "message/stream"
            @request_handler.on_message_send_stream(request.params, context)
          when "tasks/get"
            @request_handler.on_get_task(request.params, context)
          when "tasks/cancel"
            @request_handler.on_cancel_task(request.params, context)
          when "tasks/resubscribe"
            @request_handler.on_resubscribe_to_task(request.params, context)
          when "tasks/pushNotificationConfig/set"
            @request_handler.on_set_task_push_notification_config(request.params, context)
          when "tasks/pushNotificationConfig/get"
            @request_handler.on_get_task_push_notification_config(request.params, context)
          when "tasks/pushNotificationConfig/list"
            @request_handler.on_list_task_push_notification_config(request.params, context)
          when "tasks/pushNotificationConfig/delete"
            @request_handler.on_delete_task_push_notification_config(request.params, context)
          else
            raise A2A::Errors::MethodNotFound, "Method '#{request.method}' not found"
          end
        end

        ##
        # Build server context from Rack request
        #
        # @param request [Rack::Request] The Rack request
        # @return [A2A::Server::Context] The server context
        def build_server_context(request)
          context = A2A::Server::Context.new

          # Extract user information if available (depends on authentication middleware)
          if request.env["warden"]&.authenticated?
            context.set_user(request.env["warden"].user)
            context.set_authentication("warden", request.env["warden"])
          elsif request.env["current_user"]
            context.set_user(request.env["current_user"])
          end

          # Set request metadata
          context.set_metadata(:remote_addr, request.ip)
          context.set_metadata(:user_agent, request.user_agent)
          context.set_metadata(:headers, request.env.select { |k, _| k.start_with?("HTTP_") })

          context
        end

        ##
        # Create a JSON response
        #
        # @param status [Integer] HTTP status code
        # @param data [Object] Data to serialize as JSON
        # @return [Array] Rack response
        def json_response(status, data)
          headers = {
            "Content-Type" => "application/json",
            "Cache-Control" => "no-cache"
          }

          body = JSON.generate(data)
          [status, headers, [body]]
        end

        ##
        # Create a JSON-RPC error response
        #
        # @param id [String, Integer, nil] Request ID
        # @param code [Integer] Error code
        # @param message [String] Error message
        # @param data [Object, nil] Optional error data
        # @return [Array] Rack response
        def json_rpc_error_response(id, code, message, data = nil)
          error_data = A2A::Protocol::JsonRpc.build_error_response(
            code: code,
            message: message,
            data: data,
            id: id
          )
          json_response(200, error_data)
        end

        ##
        # Create a streaming response using Server-Sent Events
        #
        # @param enumerator [Enumerator] The enumerator yielding events
        # @return [Array] Rack response
        def streaming_response(enumerator)
          headers = {
            "Content-Type" => "text/event-stream",
            "Cache-Control" => "no-cache",
            "Connection" => "keep-alive"
          }

          # Create streaming body
          body = Enumerator.new do |yielder|
            enumerator.each do |event|
              event_data = if event.respond_to?(:to_h)
                             event.to_h
                           else
                             event
                           end

              yielder << "data: #{JSON.generate(event_data)}\n\n"
            end
          rescue StandardError => e
            error_event = {
              error: {
                code: A2A::Protocol::JsonRpc::INTERNAL_ERROR,
                message: e.message
              }
            }
            yielder << "data: #{JSON.generate(error_event)}\n\n"
          ensure
            yielder << "data: [DONE]\n\n"
          end

          [200, headers, body]
        end

        ##
        # Create a 404 Not Found response
        #
        # @return [Array] Rack response
        def not_found_response
          error_response(404, "Not Found")
        end

        ##
        # Create a 405 Method Not Allowed response
        #
        # @return [Array] Rack response
        def method_not_allowed_response
          error_response(405, "Method Not Allowed")
        end

        ##
        # Create an error response
        #
        # @param status [Integer] HTTP status code
        # @param message [String] Error message
        # @return [Array] Rack response
        def error_response(status, message)
          headers = { "Content-Type" => "application/json" }
          body = JSON.generate({ error: message })
          [status, headers, [body]]
        end
      end
    end
  end
end
