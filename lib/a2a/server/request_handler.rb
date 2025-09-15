# frozen_string_literal: true

require_relative "../types"
require_relative "../errors"

module A2A
  module Server
    ##
    # Abstract base class for A2A request handlers
    #
    # This interface defines the methods that an A2A server implementation must
    # provide to handle incoming JSON-RPC requests. It mirrors the Python
    # RequestHandler interface for consistency.
    #
    class RequestHandler
      ##
      # Handle the 'tasks/get' method
      #
      # Retrieves the state and history of a specific task.
      #
      # @param params [Hash] Parameters specifying the task ID and optionally history length
      # @param context [A2A::Server::Context, nil] Context provided by the server
      # @return [A2A::Types::Task, nil] The Task object if found, otherwise nil
      # @abstract Subclasses must implement this method
      def on_get_task(params, context = nil)
        raise NotImplementedError, "Subclasses must implement on_get_task"
      end

      ##
      # Handle the 'tasks/cancel' method
      #
      # Requests the agent to cancel an ongoing task.
      #
      # @param params [Hash] Parameters specifying the task ID
      # @param context [A2A::Server::Context, nil] Context provided by the server
      # @return [A2A::Types::Task, nil] The Task object with its status updated to canceled, or nil if not found
      # @abstract Subclasses must implement this method
      def on_cancel_task(params, context = nil)
        raise NotImplementedError, "Subclasses must implement on_cancel_task"
      end

      ##
      # Handle the 'message/send' method (non-streaming)
      #
      # Sends a message to the agent to create, continue, or restart a task,
      # and waits for the final result (Task or Message).
      #
      # @param params [Hash] Parameters including the message and configuration
      # @param context [A2A::Server::Context, nil] Context provided by the server
      # @return [A2A::Types::Task, A2A::Types::Message] The final Task object or a final Message object
      # @abstract Subclasses must implement this method
      def on_message_send(params, context = nil)
        raise NotImplementedError, "Subclasses must implement on_message_send"
      end

      ##
      # Handle the 'message/stream' method (streaming)
      #
      # Sends a message to the agent and yields stream events as they are
      # produced (Task updates, Message chunks, Artifact updates).
      #
      # @param params [Hash] Parameters including the message and configuration
      # @param context [A2A::Server::Context, nil] Context provided by the server
      # @return [Enumerator] Enumerator yielding Event objects from the agent's execution
      # @abstract Subclasses must implement this method
      def on_message_send_stream(_params, _context = nil)
        raise A2A::Errors::UnsupportedOperation, "Streaming not supported by this handler"
      end

      ##
      # Handle the 'tasks/pushNotificationConfig/set' method
      #
      # Sets or updates the push notification configuration for a task.
      #
      # @param params [Hash] Parameters including the task ID and push notification configuration
      # @param context [A2A::Server::Context, nil] Context provided by the server
      # @return [A2A::Types::TaskPushNotificationConfig] The provided TaskPushNotificationConfig upon success
      # @abstract Subclasses must implement this method
      def on_set_task_push_notification_config(params, context = nil)
        raise NotImplementedError, "Subclasses must implement on_set_task_push_notification_config"
      end

      ##
      # Handle the 'tasks/pushNotificationConfig/get' method
      #
      # Retrieves the current push notification configuration for a task.
      #
      # @param params [Hash] Parameters including the task ID
      # @param context [A2A::Server::Context, nil] Context provided by the server
      # @return [A2A::Types::TaskPushNotificationConfig] The TaskPushNotificationConfig for the task
      # @abstract Subclasses must implement this method
      def on_get_task_push_notification_config(params, context = nil)
        raise NotImplementedError, "Subclasses must implement on_get_task_push_notification_config"
      end

      ##
      # Handle the 'tasks/resubscribe' method
      #
      # Allows a client to re-subscribe to a running streaming task's event stream.
      #
      # @param params [Hash] Parameters including the task ID
      # @param context [A2A::Server::Context, nil] Context provided by the server
      # @return [Enumerator] Enumerator yielding Event objects from the agent's ongoing execution
      # @abstract Subclasses must implement this method
      def on_resubscribe_to_task(_params, _context = nil)
        raise A2A::Errors::UnsupportedOperation, "Task resubscription not supported by this handler"
      end

      ##
      # Handle the 'tasks/pushNotificationConfig/list' method
      #
      # Retrieves the current push notification configurations for a task.
      #
      # @param params [Hash] Parameters including the task ID
      # @param context [A2A::Server::Context, nil] Context provided by the server
      # @return [Array<A2A::Types::TaskPushNotificationConfig>] The list of TaskPushNotificationConfig for the task
      # @abstract Subclasses must implement this method
      def on_list_task_push_notification_config(params, context = nil)
        raise NotImplementedError, "Subclasses must implement on_list_task_push_notification_config"
      end

      ##
      # Handle the 'tasks/pushNotificationConfig/delete' method
      #
      # Deletes a push notification configuration associated with a task.
      #
      # @param params [Hash] Parameters including the task ID and config ID
      # @param context [A2A::Server::Context, nil] Context provided by the server
      # @return [void]
      # @abstract Subclasses must implement this method
      def on_delete_task_push_notification_config(params, context = nil)
        raise NotImplementedError, "Subclasses must implement on_delete_task_push_notification_config"
      end
    end
  end
end
