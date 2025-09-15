# frozen_string_literal: true

module A2A
  module Client
    ##
    # API methods for A2A HTTP client
    #
    module ApiMethods
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

        request = build_json_rpc_request("tasks/get", params)
        response = execute_with_middleware(request, context || {}) do |req, _ctx|
          send_json_rpc_request(req)
        end

        ensure_task(response["result"])
      end

      ##
      # Cancel a task
      #
      # @param task_id [String] The task ID to cancel
      # @param context [Hash, nil] Optional context information
      # @return [Task] The updated task
      def cancel_task(task_id, context: nil)
        request = build_json_rpc_request("tasks/cancel", { id: task_id })
        response = execute_with_middleware(request, context || {}) do |req, _ctx|
          send_json_rpc_request(req)
        end

        ensure_task(response["result"])
      end

      ##
      # Get the agent card
      #
      # @param context [Hash, nil] Optional context information
      # @param authenticated [Boolean] Whether to get authenticated extended card
      # @return [AgentCard] The agent card
      def get_card(context: nil, authenticated: false)
        if authenticated
          request = build_json_rpc_request("agent/getAuthenticatedExtendedCard", {})
          response = execute_with_middleware(request, context || {}) do |req, _ctx|
            send_json_rpc_request(req)
          end
          ensure_agent_card(response["result"])
        else
          # Use HTTP GET for basic agent card
          response = execute_with_middleware({}, context || {}) do |_req, _ctx|
            @connection.get("/agent-card") do |request|
              request.headers.merge!(@config.all_headers)
            end
          end

          raise A2A::Errors::HTTPError, "HTTP #{response.status}: #{response.body}" unless response.success?

          ensure_agent_card(JSON.parse(response.body))

        end
      end

      ##
      # Resubscribe to a task
      #
      # @param task_id [String] The task ID to resubscribe to
      # @param context [Hash, nil] Optional context information
      # @return [Task] The task
      def resubscribe(task_id, context: nil)
        request = build_json_rpc_request("tasks/resubscribe", { id: task_id })
        response = execute_with_middleware(request, context || {}) do |req, _ctx|
          send_json_rpc_request(req)
        end

        ensure_task(response["result"])
      end

      ##
      # Set a task callback (deprecated - use set_task_push_notification_config)
      #
      # @param task_id [String] The task ID
      # @param push_notification_config [Hash] The push notification configuration
      # @param context [Hash, nil] Optional context information
      # @return [Hash] The response
      def set_task_callback(task_id, push_notification_config, context: nil)
        params = {
          taskId: task_id,
          pushNotificationConfig: push_notification_config
        }

        request = build_json_rpc_request("tasks/pushNotificationConfig/set", params)
        response = execute_with_middleware(request, context || {}) do |req, _ctx|
          send_json_rpc_request(req)
        end

        response["result"]
      end

      ##
      # Get a task callback (deprecated - use get_task_push_notification_config)
      #
      # @param task_id [String] The task ID
      # @param push_notification_config_id [String] The config ID
      # @param context [Hash, nil] Optional context information
      # @return [Hash] The configuration
      def get_task_callback(task_id, push_notification_config_id, context: nil)
        params = {
          taskId: task_id,
          pushNotificationConfigId: push_notification_config_id
        }

        request = build_json_rpc_request("tasks/pushNotificationConfig/get", params)
        response = execute_with_middleware(request, context || {}) do |req, _ctx|
          send_json_rpc_request(req)
        end

        response["result"]
      end

      ##
      # List task callbacks (deprecated - use list_task_push_notification_configs)
      #
      # @param task_id [String] The task ID
      # @param context [Hash, nil] Optional context information
      # @return [Array] List of configurations
      def list_task_callbacks(task_id, context: nil)
        params = { taskId: task_id }

        request = build_json_rpc_request("tasks/pushNotificationConfig/list", params)
        response = execute_with_middleware(request, context || {}) do |req, _ctx|
          send_json_rpc_request(req)
        end

        response["result"]
      end

      ##
      # Delete a task callback (deprecated - use delete_task_push_notification_config)
      #
      # @param task_id [String] The task ID
      # @param push_notification_config_id [String] The config ID
      # @param context [Hash, nil] Optional context information
      # @return [Boolean] Success status
      def delete_task_callback(task_id, push_notification_config_id, context: nil)
        params = {
          taskId: task_id,
          pushNotificationConfigId: push_notification_config_id
        }

        request = build_json_rpc_request("tasks/pushNotificationConfig/delete", params)
        response = execute_with_middleware(request, context || {}) do |req, _ctx|
          send_json_rpc_request(req)
        end

        response["result"]
      end

      ##
      # Set a push notification config for a task
      #
      # @param task_id [String] The task ID
      # @param config [Hash] The push notification configuration
      # @param context [Hash, nil] Optional context information
      # @return [Hash] The response
      def set_task_push_notification_config(task_id, config, context: nil)
        params = {
          taskId: task_id,
          pushNotificationConfig: config
        }

        request = build_json_rpc_request("tasks/pushNotificationConfig/set", params)
        response = execute_with_middleware(request, context || {}) do |req, _ctx|
          send_json_rpc_request(req)
        end

        response["result"]
      end

      ##
      # Get a push notification config for a task
      #
      # @param task_id [String] The task ID
      # @param config_id [String] The config ID
      # @param context [Hash, nil] Optional context information
      # @return [Hash] The configuration
      def get_task_push_notification_config(task_id, config_id, context: nil)
        params = {
          taskId: task_id,
          pushNotificationConfigId: config_id
        }

        request = build_json_rpc_request("tasks/pushNotificationConfig/get", params)
        response = execute_with_middleware(request, context || {}) do |req, _ctx|
          send_json_rpc_request(req)
        end

        response["result"]
      end

      ##
      # List push notification configs for a task
      #
      # @param task_id [String] The task ID
      # @param context [Hash, nil] Optional context information
      # @return [Array] List of configurations
      def list_task_push_notification_configs(task_id, context: nil)
        params = { taskId: task_id }

        request = build_json_rpc_request("tasks/pushNotificationConfig/list", params)
        response = execute_with_middleware(request, context || {}) do |req, _ctx|
          send_json_rpc_request(req)
        end

        response["result"]
      end

      ##
      # Delete a push notification config for a task
      #
      # @param task_id [String] The task ID
      # @param config_id [String] The config ID
      # @param context [Hash, nil] Optional context information
      # @return [Boolean] Success status
      def delete_task_push_notification_config(task_id, config_id, context: nil)
        params = {
          taskId: task_id,
          pushNotificationConfigId: config_id
        }

        request = build_json_rpc_request("tasks/pushNotificationConfig/delete", params)
        response = execute_with_middleware(request, context || {}) do |req, _ctx|
          send_json_rpc_request(req)
        end

        response["result"]
      end
    end
  end
end
