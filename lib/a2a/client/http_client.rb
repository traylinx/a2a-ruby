# frozen_string_literal: true

require 'faraday'
require 'json'
require 'securerandom'
require_relative 'base'

# Try to use connection pooling adapter if available
begin
  require 'net/http/persistent'
  HTTP_ADAPTER = :net_http_persistent
rescue LoadError
  HTTP_ADAPTER = Faraday.default_adapter
end

module A2A
  module Client
    ##
    # HTTP client implementation for A2A protocol
    #
    # Provides JSON-RPC 2.0 over HTTP(S) communication with A2A agents,
    # including support for streaming responses via Server-Sent Events.
    #
    class HttpClient < Base
      attr_reader :endpoint_url, :connection

      ##
      # Initialize a new HTTP client
      #
      # @param endpoint_url [String] The base URL for the A2A agent
      # @param config [Config, nil] Client configuration
      # @param middleware [Array] List of middleware interceptors
      # @param consumers [Array] List of event consumers
      def initialize(endpoint_url, config: nil, middleware: [], consumers: [])
        super(config: config, middleware: middleware, consumers: consumers)
        @endpoint_url = endpoint_url.chomp('/')
        @connection = build_connection
        @request_id_counter = 0
        @request_id_mutex = Mutex.new
        @connection_pool = nil
        @performance_stats = {
          requests_count: 0,
          total_time: 0.0,
          avg_response_time: 0.0,
          cache_hits: 0,
          cache_misses: 0
        }
        @stats_mutex = Mutex.new
      end

      ##
      # Send a message to the agent
      #
      # @param message [Message, Hash] The message to send
      # @param context [Hash, nil] Optional context information
      # @return [Enumerator, Message] Stream of responses or single response
      def send_message(message, context: nil)
        message = ensure_message(message)
        
        if @config.streaming?
          send_streaming_message(message, context)
        else
          send_sync_message(message, context)
        end
      end

      ##
      # Get a task by ID
      #
      # @param task_id [String] The task ID
      # @param context [Hash, nil] Optional context information
      # @param history_length [Integer, nil] Maximum number of history messages to include
      # @return [Task] The task
      def get_task(task_id, context: nil, history_length: nil)
        params = { id: task_id }
        params[:historyLength] = history_length if history_length

        request = build_json_rpc_request('tasks/get', params)
        response = execute_with_middleware(request, context || {}) do |req, ctx|
          send_json_rpc_request(req)
        end

        ensure_task(response['result'])
      end

      ##
      # Cancel a task
      #
      # @param task_id [String] The task ID to cancel
      # @param context [Hash, nil] Optional context information
      # @return [Task] The updated task
      def cancel_task(task_id, context: nil)
        request = build_json_rpc_request('tasks/cancel', { id: task_id })
        response = execute_with_middleware(request, context || {}) do |req, ctx|
          send_json_rpc_request(req)
        end

        ensure_task(response['result'])
      end

      ##
      # Get the agent card
      #
      # @param context [Hash, nil] Optional context information
      # @param authenticated [Boolean] Whether to get authenticated extended card
      # @return [AgentCard] The agent card
      def get_card(context: nil, authenticated: false)
        if authenticated
          request = build_json_rpc_request('agent/getAuthenticatedExtendedCard', {})
          response = execute_with_middleware(request, context || {}) do |req, ctx|
            send_json_rpc_request(req)
          end
          ensure_agent_card(response['result'])
        else
          # Use HTTP GET for basic agent card
          response = execute_with_middleware({}, context || {}) do |req, ctx|
            @connection.get('/agent-card') do |request|
              request.headers.merge!(@config.all_headers)
            end
          end

          if response.success?
            ensure_agent_card(JSON.parse(response.body))
          else
            raise A2A::Errors::HTTPError.new(
              "Failed to get agent card: #{response.status}",
              status_code: response.status,
              response_body: response.body
            )
          end
        end
      end

      ##
      # Resubscribe to a task for streaming updates
      #
      # @param task_id [String] The task ID to resubscribe to
      # @param context [Hash, nil] Optional context information
      # @return [Enumerator] Stream of task updates
      def resubscribe(task_id, context: nil)
        request = build_json_rpc_request('tasks/resubscribe', { id: task_id })
        
        execute_with_middleware(request, context || {}) do |req, ctx|
          send_streaming_request(req)
        end
      end

      ##
      # Set a callback for task updates
      #
      # @param task_id [String] The task ID
      # @param push_notification_config [PushNotificationConfig, Hash] The push notification configuration
      # @param context [Hash, nil] Optional context information
      # @return [void]
      def set_task_callback(task_id, push_notification_config, context: nil)
        config = push_notification_config.is_a?(A2A::Types::PushNotificationConfig) ?
          push_notification_config : A2A::Types::PushNotificationConfig.from_h(push_notification_config)

        params = {
          taskId: task_id,
          pushNotificationConfig: config.to_h
        }

        request = build_json_rpc_request('tasks/pushNotificationConfig/set', params)
        execute_with_middleware(request, context || {}) do |req, ctx|
          send_json_rpc_request(req)
        end
      end

      ##
      # Get the callback configuration for a task
      #
      # @param task_id [String] The task ID
      # @param push_notification_config_id [String] The push notification config ID
      # @param context [Hash, nil] Optional context information
      # @return [TaskPushNotificationConfig] The callback configuration
      def get_task_callback(task_id, push_notification_config_id, context: nil)
        params = {
          taskId: task_id,
          pushNotificationConfigId: push_notification_config_id
        }

        request = build_json_rpc_request('tasks/pushNotificationConfig/get', params)
        response = execute_with_middleware(request, context || {}) do |req, ctx|
          send_json_rpc_request(req)
        end

        A2A::Types::TaskPushNotificationConfig.from_h(response['result'])
      end

      ##
      # List all callback configurations for a task
      #
      # @param task_id [String] The task ID
      # @param context [Hash, nil] Optional context information
      # @return [Array<TaskPushNotificationConfig>] List of callback configurations
      def list_task_callbacks(task_id, context: nil)
        request = build_json_rpc_request('tasks/pushNotificationConfig/list', { taskId: task_id })
        response = execute_with_middleware(request, context || {}) do |req, ctx|
          send_json_rpc_request(req)
        end

        response['result'].map { |config| A2A::Types::TaskPushNotificationConfig.from_h(config) }
      end

      ##
      # Delete a callback configuration for a task
      #
      # @param task_id [String] The task ID
      # @param push_notification_config_id [String] The push notification config ID
      # @param context [Hash, nil] Optional context information
      # @return [void]
      def delete_task_callback(task_id, push_notification_config_id, context: nil)
        params = {
          taskId: task_id,
          pushNotificationConfigId: push_notification_config_id
        }

        request = build_json_rpc_request('tasks/pushNotificationConfig/delete', params)
        execute_with_middleware(request, context || {}) do |req, ctx|
          send_json_rpc_request(req)
        end
      end

      private

      ##
      # Build the Faraday connection with performance optimizations
      #
      # @return [Faraday::Connection] The configured connection
      def build_connection
        Faraday.new(@endpoint_url) do |conn|
          # Request middleware
          conn.request :json
          
          # Response middleware
          conn.response :json, content_type: /\bjson$/
          
          # Use connection pooling adapter if available
          conn.adapter HTTP_ADAPTER
          
          # Set timeouts
          conn.options.timeout = @config.timeout
          conn.options.read_timeout = @config.timeout
          conn.options.write_timeout = @config.timeout
          
          # Performance optimizations
          conn.options.keep_alive_timeout = 30
          conn.options.pool_size = @config.pool_size || 5
          
          # Enable compression if supported
          conn.headers['Accept-Encoding'] = 'gzip, deflate'
          
          # Set keep-alive headers
          conn.headers['Connection'] = 'keep-alive'
          conn.headers['Keep-Alive'] = 'timeout=30, max=100'
        end
      end

      ##
      # Send a synchronous message
      #
      # @param message [Message] The message to send
      # @param context [Hash] The request context
      # @return [Message] The response message
      def send_sync_message(message, context)
        request = build_json_rpc_request('message/send', message.to_h)
        response = execute_with_middleware(request, context) do |req, ctx|
          send_json_rpc_request(req)
        end

        ensure_message(response['result'])
      end

      ##
      # Send a streaming message
      #
      # @param message [Message] The message to send
      # @param context [Hash] The request context
      # @return [Enumerator] Stream of response messages
      def send_streaming_message(message, context)
        request = build_json_rpc_request('message/stream', message.to_h)
        
        execute_with_middleware(request, context) do |req, ctx|
          send_streaming_request(req)
        end
      end

      ##
      # Send a JSON-RPC request and get response
      #
      # @param request [Hash] The JSON-RPC request
      # @return [Hash] The JSON-RPC response
      def send_json_rpc_request(request)
        response = @connection.post do |req|
          req.headers.merge!(@config.all_headers)
          req.headers['Content-Type'] = 'application/json'
          req.body = request.to_json
        end

        handle_http_response(response)
      end

      ##
      # Send a streaming request using Server-Sent Events
      #
      # @param request [Hash] The JSON-RPC request
      # @return [Enumerator] Stream of events
      def send_streaming_request(request)
        Enumerator.new do |yielder|
          response = @connection.post do |req|
            req.headers.merge!(@config.all_headers)
            req.headers['Content-Type'] = 'application/json'
            req.headers['Accept'] = 'text/event-stream'
            req.body = request.to_json
            
            # Handle streaming response
            req.options.on_data = proc do |chunk, size|
              events = parse_sse_chunk(chunk)
              events.each do |event|
                case event[:event]
                when 'message'
                  yielder << ensure_message(JSON.parse(event[:data]))
                when 'task_status_update'
                  event_data = A2A::Types::TaskStatusUpdateEvent.from_h(JSON.parse(event[:data]))
                  process_event(event_data)
                  yielder << event_data
                when 'task_artifact_update'
                  event_data = A2A::Types::TaskArtifactUpdateEvent.from_h(JSON.parse(event[:data]))
                  process_event(event_data)
                  yielder << event_data
                when 'error'
                  error_data = JSON.parse(event[:data])
                  error = A2A::Errors::ErrorUtils.from_json_rpc_code(
                    error_data['code'],
                    error_data['message'],
                    data: error_data['data']
                  )
                  raise error
                end
              end
            end
          end

          unless response.success?
            raise A2A::Errors::HTTPError.new(
              "Streaming request failed: #{response.status}",
              status_code: response.status,
              response_body: response.body
            )
          end
        end
      end

      ##
      # Handle HTTP response and extract JSON-RPC result
      #
      # @param response [Faraday::Response] The HTTP response
      # @return [Hash] The JSON-RPC response
      def handle_http_response(response)
        unless response.success?
          raise A2A::Errors::HTTPError.new(
            "HTTP request failed: #{response.status}",
            status_code: response.status,
            response_body: response.body
          )
        end

        begin
          json_response = response.body.is_a?(Hash) ? response.body : JSON.parse(response.body)
        rescue JSON::ParserError => e
          raise A2A::Errors::JSONError.new("Invalid JSON response: #{e.message}")
        end

        # Check for JSON-RPC error
        if json_response['error']
          error = json_response['error']
          raise A2A::Errors::ErrorUtils.from_json_rpc_code(
            error['code'],
            error['message'],
            data: error['data']
          )
        end

        json_response
      end

      ##
      # Parse Server-Sent Events chunk
      #
      # @param chunk [String] The SSE chunk
      # @return [Array<Hash>] Parsed events
      def parse_sse_chunk(chunk)
        events = []
        current_event = {}

        chunk.split("\n").each do |line|
          line = line.strip
          next if line.empty?

          if line.start_with?('data: ')
            current_event[:data] = line[6..-1]
          elsif line.start_with?('event: ')
            current_event[:event] = line[7..-1]
          elsif line.start_with?('id: ')
            current_event[:id] = line[4..-1]
          elsif line.start_with?('retry: ')
            current_event[:retry] = line[7..-1].to_i
          elsif line == ''
            # Empty line indicates end of event
            events << current_event.dup if current_event[:data]
            current_event.clear
          end
        end

        # Handle case where chunk doesn't end with empty line
        events << current_event if current_event[:data]
        events
      end

      ##
      # Build a JSON-RPC request
      #
      # @param method [String] The method name
      # @param params [Hash] The method parameters
      # @return [A2A::Protocol::Request] The JSON-RPC request
      def build_json_rpc_request(method, params = {})
        A2A::Protocol::Request.new(
          jsonrpc: A2A::Protocol::JsonRpc::JSONRPC_VERSION,
          method: method,
          params: params,
          id: next_request_id
        )
      end

      ##
      # Generate next request ID
      #
      # @return [Integer] The next request ID
      def next_request_id
        @request_id_mutex.synchronize do
          @request_id_counter += 1
        end
      end

      ##
      # Get performance statistics
      #
      # @return [Hash] Performance statistics
      def performance_stats
        @stats_mutex.synchronize { @performance_stats.dup }
      end

      ##
      # Reset performance statistics
      #
      def reset_performance_stats!
        @stats_mutex.synchronize do
          @performance_stats = {
            requests_count: 0,
            total_time: 0.0,
            avg_response_time: 0.0,
            cache_hits: 0,
            cache_misses: 0
          }
        end
      end

      ##
      # Record request performance metrics
      #
      # @param duration [Float] Request duration in seconds
      def record_request_performance(duration)
        @stats_mutex.synchronize do
          @performance_stats[:requests_count] += 1
          @performance_stats[:total_time] += duration
          @performance_stats[:avg_response_time] = 
            @performance_stats[:total_time] / @performance_stats[:requests_count]
        end
      end
    end
  end
end