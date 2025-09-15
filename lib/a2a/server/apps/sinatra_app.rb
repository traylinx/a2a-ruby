# frozen_string_literal: true

begin
  require "sinatra/base"
rescue LoadError
  raise LoadError, "Sinatra is required for A2A::Server::Apps::SinatraApp. Install with: gem install sinatra"
end

require "json"
require_relative "../request_handler"
require_relative "../../protocol/json_rpc"

module A2A
  module Server
    module Apps
      ##
      # Sinatra application for serving A2A protocol endpoints
      #
      # This class provides a Sinatra-based application that can handle
      # A2A JSON-RPC requests and serve agent cards. It's a more Ruby-idiomatic
      # alternative to the Rack app.
      #
      class SinatraApp < Sinatra::Base
        set :show_exceptions, false
        set :raise_errors, false

        class << self
          attr_accessor :agent_card, :request_handler, :extended_agent_card, :card_modifier, :extended_card_modifier

          ##
          # Configure the Sinatra app with A2A components
          #
          # @param agent_card [A2A::Types::AgentCard] The agent card
          # @param request_handler [RequestHandler] The request handler
          # @param extended_agent_card [A2A::Types::AgentCard, nil] Optional extended agent card
          # @param card_modifier [Proc, nil] Optional card modifier
          # @param extended_card_modifier [Proc, nil] Optional extended card modifier
          def configure_a2a(agent_card:, request_handler:, extended_agent_card: nil, card_modifier: nil,
                            extended_card_modifier: nil)
            self.agent_card = agent_card
            self.request_handler = request_handler
            self.extended_agent_card = extended_agent_card
            self.card_modifier = card_modifier
            self.extended_card_modifier = extended_card_modifier
          end
        end

        # Agent card endpoint
        get "/.well-known/a2a/agent-card" do
          content_type :json

          card_to_serve = self.class.agent_card
          card_to_serve = self.class.card_modifier.call(card_to_serve) if self.class.card_modifier

          JSON.generate(card_to_serve.to_h)
        end

        # Extended agent card endpoint
        get "/a2a/agent-card/extended" do
          content_type :json

          unless self.class.agent_card.supports_authenticated_extended_card
            halt 404, JSON.generate({ error: "Extended agent card not supported" })
          end

          # Build server context
          context = build_server_context

          card_to_serve = self.class.extended_agent_card || self.class.agent_card

          card_to_serve = self.class.extended_card_modifier.call(card_to_serve, context) if self.class.extended_card_modifier

          JSON.generate(card_to_serve.to_h)
        end

        # JSON-RPC endpoint
        post "/a2a/rpc" do
          content_type :json

          # Validate content type
          unless request.content_type&.include?("application/json")
            halt 400, JSON.generate({ error: "Content-Type must be application/json" })
          end

          # Parse request body
          begin
            request.body.rewind
            json_data = JSON.parse(request.body.read)
          rescue JSON::ParserError => e
            return json_rpc_error_response(nil, A2A::Protocol::JsonRpc::PARSE_ERROR, "Parse error: #{e.message}")
          end

          # Validate JSON-RPC structure
          begin
            rpc_request = A2A::Protocol::JsonRpc.parse_request(json_data)
          rescue A2A::Errors::A2AError => e
            return json_rpc_error_response(json_data["id"], e.code, e.message, e.data)
          end

          # Build server context
          context = build_server_context

          # Route to appropriate handler method
          begin
            result = route_request(rpc_request, context)

            # Handle streaming responses
            return handle_streaming_response(result) if result.is_a?(Enumerator)

            # Return regular JSON-RPC response
            response_data = A2A::Protocol::JsonRpc.build_response(
              result: result,
              id: rpc_request.id
            )
            JSON.generate(response_data)
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

        # Error handlers
        error A2A::Errors::A2AError do
          content_type :json
          error = env["sinatra.error"]
          status 400
          JSON.generate({
                          error: {
                            code: error.code,
                            message: error.message,
                            data: error.data
                          }
                        })
        end

        error StandardError do
          content_type :json
          error = env["sinatra.error"]
          status 500
          JSON.generate({
                          error: {
                            code: A2A::Protocol::JsonRpc::INTERNAL_ERROR,
                            message: "Internal Server Error: #{error.message}"
                          }
                        })
        end

        private

        ##
        # Route JSON-RPC request to appropriate handler method
        #
        # @param request [A2A::Protocol::Request] The parsed JSON-RPC request
        # @param context [A2A::Server::Context] The server context
        # @return [Object] The result from the handler
        def route_request(request, context)
          case request.method
          when "message/send"
            self.class.request_handler.on_message_send(request.params, context)
          when "message/stream"
            self.class.request_handler.on_message_send_stream(request.params, context)
          when "tasks/get"
            self.class.request_handler.on_get_task(request.params, context)
          when "tasks/cancel"
            self.class.request_handler.on_cancel_task(request.params, context)
          when "tasks/resubscribe"
            self.class.request_handler.on_resubscribe_to_task(request.params, context)
          when "tasks/pushNotificationConfig/set"
            self.class.request_handler.on_set_task_push_notification_config(request.params, context)
          when "tasks/pushNotificationConfig/get"
            self.class.request_handler.on_get_task_push_notification_config(request.params, context)
          when "tasks/pushNotificationConfig/list"
            self.class.request_handler.on_list_task_push_notification_config(request.params, context)
          when "tasks/pushNotificationConfig/delete"
            self.class.request_handler.on_delete_task_push_notification_config(request.params, context)
          else
            raise A2A::Errors::MethodNotFound, "Method '#{request.method}' not found"
          end
        end

        ##
        # Build server context from Sinatra request
        #
        # @return [A2A::Server::Context] The server context
        def build_server_context
          context = A2A::Server::Context.new

          # Extract user information if available
          if respond_to?(:current_user) && current_user
            context.set_user(current_user)
          elsif env["warden"]&.authenticated?
            context.set_user(env["warden"].user)
            context.set_authentication("warden", env["warden"])
          end

          # Set request metadata
          context.set_metadata(:remote_addr, request.ip)
          context.set_metadata(:user_agent, request.user_agent)
          context.set_metadata(:headers, request.env.select { |k, _| k.start_with?("HTTP_") })

          context
        end

        ##
        # Create a JSON-RPC error response
        #
        # @param id [String, Integer, nil] Request ID
        # @param code [Integer] Error code
        # @param message [String] Error message
        # @param data [Object, nil] Optional error data
        # @return [String] JSON response
        def json_rpc_error_response(id, code, message, data = nil)
          error_data = A2A::Protocol::JsonRpc.build_error_response(
            code: code,
            message: message,
            data: data,
            id: id
          )
          JSON.generate(error_data)
        end

        ##
        # Handle streaming response using Server-Sent Events
        #
        # @param enumerator [Enumerator] The enumerator yielding events
        # @return [String] SSE response
        def handle_streaming_response(enumerator)
          content_type "text/event-stream"
          headers "Cache-Control" => "no-cache", "Connection" => "keep-alive"

          stream do |out|
            enumerator.each do |event|
              event_data = if event.respond_to?(:to_h)
                             event.to_h
                           else
                             event
                           end

              out << "data: #{JSON.generate(event_data)}\n\n"
            end
          rescue StandardError => e
            error_event = {
              error: {
                code: A2A::Protocol::JsonRpc::INTERNAL_ERROR,
                message: e.message
              }
            }
            out << "data: #{JSON.generate(error_event)}\n\n"
          ensure
            out << "data: [DONE]\n\n"
          end
        end
      end
    end
  end
end
