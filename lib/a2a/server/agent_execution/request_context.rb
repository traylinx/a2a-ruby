# frozen_string_literal: true

module A2A
  module Server
    module AgentExecution
      ##
      # Request context for agent execution
      #
      # Contains all the information needed for an agent to process a request,
      # including the message, task ID, context ID, and server call context.
      #
      class RequestContext
        attr_reader :message, :task_id, :context_id, :server_context, :metadata

        ##
        # Initialize a new request context
        #
        # @param message [A2A::Types::Message, nil] The message that initiated the request
        # @param task_id [String, nil] The task ID if continuing an existing task
        # @param context_id [String, nil] The context ID for the conversation
        # @param server_context [A2A::Server::Context, nil] The server call context
        # @param metadata [Hash] Additional metadata for the request
        def initialize(message: nil, task_id: nil, context_id: nil, server_context: nil, metadata: {})
          @message = message
          @task_id = task_id
          @context_id = context_id || message&.context_id
          @server_context = server_context
          @metadata = metadata.dup
        end

        ##
        # Check if this is a new task (no task_id provided)
        #
        # @return [Boolean] True if this is a new task
        def new_task?
          @task_id.nil?
        end

        ##
        # Check if this is continuing an existing task
        #
        # @return [Boolean] True if continuing an existing task
        def continuing_task?
          !@task_id.nil?
        end

        ##
        # Check if this request has a message
        #
        # @return [Boolean] True if a message is present
        def has_message?
          !@message.nil?
        end

        ##
        # Get the user from the server context if available
        #
        # @return [Object, nil] The user object or nil
        def user
          @server_context&.user
        end

        ##
        # Check if the request is authenticated
        #
        # @return [Boolean] True if authenticated
        def authenticated?
          @server_context&.authenticated? || false
        end

        ##
        # Get authentication data for a specific scheme
        #
        # @param scheme [String] The authentication scheme
        # @return [Object, nil] Authentication data or nil
        def authentication(scheme)
          @server_context&.get_authentication(scheme)
        end

        ##
        # Get metadata value
        #
        # @param key [String, Symbol] The metadata key
        # @return [Object, nil] The metadata value or nil
        def get_metadata(key)
          @metadata[key] || @server_context&.get_metadata(key)
        end

        ##
        # Set metadata value
        #
        # @param key [String, Symbol] The metadata key
        # @param value [Object] The metadata value
        def set_metadata(key, value)
          @metadata[key] = value
        end

        ##
        # Convert to hash representation
        #
        # @return [Hash] Hash representation of the context
        def to_h
          {
            message: @message&.to_h,
            task_id: @task_id,
            context_id: @context_id,
            metadata: @metadata,
            authenticated: authenticated?,
            user: user&.to_s
          }
        end

        ##
        # Create a copy of this context with modifications
        #
        # @param **changes [Hash] Changes to apply
        # @return [RequestContext] New context with changes applied
        def with(**changes)
          RequestContext.new(
            message: changes[:message] || @message,
            task_id: changes[:task_id] || @task_id,
            context_id: changes[:context_id] || @context_id,
            server_context: changes[:server_context] || @server_context,
            metadata: @metadata.merge(changes[:metadata] || {})
          )
        end
      end

      ##
      # Builder for creating request contexts from various inputs
      #
      # Provides a convenient way to build RequestContext objects from
      # different types of input (JSON-RPC requests, HTTP requests, etc.)
      #
      class RequestContextBuilder
        ##
        # Build a request context from a message send request
        #
        # @param params [Hash] The message send parameters
        # @param server_context [A2A::Server::Context, nil] The server context
        # @return [RequestContext] The built request context
        def self.from_message_send(params, server_context = nil)
          message_data = params["message"] || params[:message]
          task_id = params["taskId"] || params[:task_id]
          context_id = params["contextId"] || params[:context_id]

          message = if message_data.is_a?(A2A::Types::Message)
                      message_data
                    elsif message_data.is_a?(Hash)
                      A2A::Types::Message.from_h(message_data)
                    else
                      nil
                    end

          # Extract context_id from message if not provided in params
          context_id ||= message&.context_id

          RequestContext.new(
            message: message,
            task_id: task_id,
            context_id: context_id,
            server_context: server_context,
            metadata: {
              request_type: "message_send",
              params: params
            }
          )
        end

        ##
        # Build a request context from a task operation request
        #
        # @param params [Hash] The task operation parameters
        # @param server_context [A2A::Server::Context, nil] The server context
        # @param operation [String] The operation type (e.g., 'get', 'cancel')
        # @return [RequestContext] The built request context
        def self.from_task_operation(params, server_context = nil, operation: "get")
          task_id = params["id"] || params[:id] || params["taskId"] || params[:task_id]
          context_id = params["contextId"] || params[:context_id]

          RequestContext.new(
            task_id: task_id,
            context_id: context_id,
            server_context: server_context,
            metadata: {
              request_type: "task_#{operation}",
              params: params
            }
          )
        end

        ##
        # Build a request context from a streaming message request
        #
        # @param params [Hash] The streaming message parameters
        # @param server_context [A2A::Server::Context, nil] The server context
        # @return [RequestContext] The built request context
        def self.from_streaming_message(params, server_context = nil)
          context = from_message_send(params, server_context)
          context.set_metadata(:streaming, true)
          context.set_metadata(:request_type, "message_stream")
          context
        end

        ##
        # Build a request context from a task resubscription request
        #
        # @param params [Hash] The resubscription parameters
        # @param server_context [A2A::Server::Context, nil] The server context
        # @return [RequestContext] The built request context
        def self.from_task_resubscription(params, server_context = nil)
          context = from_task_operation(params, server_context, operation: "resubscribe")
          context.set_metadata(:streaming, true)
          context
        end
      end
    end
  end
end
