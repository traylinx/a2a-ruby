# frozen_string_literal: true

require_relative "../types"
require_relative "../errors"
require_relative "task_manager"
require_relative "push_notification_manager"

##
# Standard A2A protocol method implementations
#
# This module provides implementations for all core A2A JSON-RPC methods
# including message handling, task management, and push notifications.
#
module A2A::Server::A2AMethods
  def self.included(base)
    base.extend(ClassMethods)

    # Register all standard A2A methods when included
    base.register_a2a_methods
  end

  module ClassMethods
    ##
    # Register all standard A2A protocol methods
    def register_a2a_methods
      # Core messaging methods
      a2a_method "message/send" do |params, context|
        handle_message_send(params, context)
      end

      a2a_method "message/stream", streaming: true do |params, context|
        handle_message_stream(params, context)
      end

      # Task management methods
      a2a_method "tasks/get" do |params, context|
        handle_tasks_get(params, context)
      end

      a2a_method "tasks/cancel" do |params, context|
        handle_tasks_cancel(params, context)
      end

      a2a_method "tasks/resubscribe", streaming: true do |params, context|
        handle_tasks_resubscribe(params, context)
      end

      # Push notification methods
      a2a_method "tasks/pushNotificationConfig/set" do |params, context|
        handle_push_notification_config_set(params, context)
      end

      a2a_method "tasks/pushNotificationConfig/get" do |params, context|
        handle_push_notification_config_get(params, context)
      end

      a2a_method "tasks/pushNotificationConfig/list" do |params, context|
        handle_push_notification_config_list(params, context)
      end

      a2a_method "tasks/pushNotificationConfig/delete" do |params, context|
        handle_push_notification_config_delete(params, context)
      end

      # Agent card methods
      a2a_method "agent/getCard" do |params, context|
        handle_agent_get_card(params, context)
      end

      a2a_method "agent/getAuthenticatedExtendedCard" do |params, context|
        handle_agent_get_authenticated_extended_card(params, context)
      end
    end
  end

  ##
  # Handle message/send method
  #
  # @param params [Hash] Method parameters
  # @param context [A2A::Server::Context] Request context
  # @return [Hash] Response with task information
  def handle_message_send(params, context)
    validate_required_params(params, %w[message])

    message_data = params["message"]
    blocking = params.fetch("blocking", true)

    # Parse message
    message = A2A::Types::Message.from_h(message_data)

    # Create task for message processing
    task = task_manager.create_task(
      type: "message_processing",
      params: { message: message.to_h, blocking: blocking },
      context_id: message.context_id,
      metadata: {
        message_id: message.message_id,
        role: message.role
      }
    )

    # Process message (delegate to subclass implementation)
    if blocking
      # Update task to working state first
      task_manager.update_task_status(
        task.id,
        A2A::Types::TaskStatus.new(
          state: A2A::Types::TASK_STATE_WORKING,
          message: "Processing message",
          updated_at: Time.now.utc.iso8601
        )
      )

      # Synchronous processing
      result = process_message_sync(message, task, context)

      # Update task with result
      task_manager.update_task_status(
        task.id,
        A2A::Types::TaskStatus.new(
          state: A2A::Types::TASK_STATE_COMPLETED,
          result: result,
          updated_at: Time.now.utc.iso8601
        )
      )

      {
        task_id: task.id,
        context_id: task.context_id,
        result: result
      }
    else
      # Asynchronous processing
      process_message_async(message, task, context)

      {
        task_id: task.id,
        context_id: task.context_id,
        status: task.status.to_h
      }
    end
  end

  ##
  # Handle message/stream method
  #
  # @param params [Hash] Method parameters
  # @param context [A2A::Server::Context] Request context
  # @return [Enumerator] Stream of responses
  def handle_message_stream(params, context)
    validate_required_params(params, %w[message])

    message_data = params["message"]
    message = A2A::Types::Message.from_h(message_data)

    # Create task for streaming message processing
    task = task_manager.create_task(
      type: "message_streaming",
      params: { message: message.to_h },
      context_id: message.context_id,
      metadata: {
        message_id: message.message_id,
        role: message.role,
        streaming: true
      }
    )

    # Return enumerator for streaming responses
    Enumerator.new do |yielder|
      # Update task to working state
      task_manager.update_task_status(
        task.id,
        A2A::Types::TaskStatus.new(
          state: A2A::Types::TASK_STATE_WORKING,
          message: "Processing message stream",
          updated_at: Time.now.utc.iso8601
        )
      )

      # Process message stream (delegate to subclass implementation)
      process_message_stream(message, task, context) do |response|
        yielder << {
          task_id: task.id,
          context_id: task.context_id,
          response: response
        }
      end

      # Mark task as completed
      task_manager.update_task_status(
        task.id,
        A2A::Types::TaskStatus.new(
          state: A2A::Types::TASK_STATE_COMPLETED,
          message: "Stream completed",
          updated_at: Time.now.utc.iso8601
        )
      )
    rescue StandardError => e
      # Mark task as failed
      task_manager.update_task_status(
        task.id,
        A2A::Types::TaskStatus.new(
          state: A2A::Types::TASK_STATE_FAILED,
          error: { message: e.message, type: e.class.name },
          updated_at: Time.now.utc.iso8601
        )
      )
      raise
    end
  end

  ##
  # Handle tasks/get method
  #
  # @param params [Hash] Method parameters
  # @param context [A2A::Server::Context] Request context
  # @return [Hash] Task information
  def handle_tasks_get(params, _context)
    validate_required_params(params, %w[id])

    task_id = params["id"]
    history_length = params["historyLength"]

    task = task_manager.get_task(task_id, history_length: history_length)

    {
      task: task.to_h
    }
  end

  ##
  # Handle tasks/cancel method
  #
  # @param params [Hash] Method parameters
  # @param context [A2A::Server::Context] Request context
  # @return [Hash] Cancellation result
  def handle_tasks_cancel(params, _context)
    validate_required_params(params, %w[id])

    task_id = params["id"]
    reason = params["reason"]

    task = task_manager.cancel_task(task_id, reason: reason)

    {
      task_id: task.id,
      status: task.status.to_h
    }
  end

  ##
  # Handle tasks/resubscribe method
  #
  # @param params [Hash] Method parameters
  # @param context [A2A::Server::Context] Request context
  # @return [Enumerator] Stream of task updates
  def handle_tasks_resubscribe(params, _context)
    validate_required_params(params, %w[id])

    task_id = params["id"]

    # Verify task exists
    task = task_manager.get_task(task_id)

    # Return enumerator for task update stream
    Enumerator.new do |yielder|
      # Register for task updates
      client_id = push_notification_manager.register_sse_client(task_id, yielder)

      begin
        # Send current task state immediately
        yielder << {
          event_type: "task_status_update",
          event_data: {
            task_id: task.id,
            context_id: task.context_id,
            status: task.status.to_h
          }
        }

        # Keep connection alive until client disconnects
        # The actual updates will be sent via the push notification manager
        loop do
          sleep 1
          # Check if client is still connected (implementation specific)
          break unless client_connected?(yielder)
        end
      ensure
        # Unregister client when done
        push_notification_manager.unregister_sse_client(task_id, client_id)
      end
    end
  end

  ##
  # Handle tasks/pushNotificationConfig/set method
  #
  # @param params [Hash] Method parameters
  # @param context [A2A::Server::Context] Request context
  # @return [Hash] Configuration result
  def handle_push_notification_config_set(params, _context)
    validate_required_params(params, %w[taskId config])

    task_id = params["taskId"]
    config_data = params["config"]

    # Verify task exists
    task_manager.get_task(task_id)

    # Create push notification config
    config = push_notification_manager.set_push_notification_config(task_id, config_data)

    {
      task_id: task_id,
      config: config.push_notification_config.to_h
    }
  end

  ##
  # Handle tasks/pushNotificationConfig/get method
  #
  # @param params [Hash] Method parameters
  # @param context [A2A::Server::Context] Request context
  # @return [Hash] Configuration information
  def handle_push_notification_config_get(params, _context)
    validate_required_params(params, %w[taskId])

    task_id = params["taskId"]
    config_id = params["configId"]

    config = push_notification_manager.get_push_notification_config(
      task_id,
      config_id: config_id
    )

    raise A2A::Errors::NotFound, "Push notification config not found" unless config

    {
      task_id: task_id,
      config: config.push_notification_config.to_h
    }
  end

  ##
  # Handle tasks/pushNotificationConfig/list method
  #
  # @param params [Hash] Method parameters
  # @param context [A2A::Server::Context] Request context
  # @return [Hash] List of configurations
  def handle_push_notification_config_list(params, _context)
    validate_required_params(params, %w[taskId])

    task_id = params["taskId"]

    configs = push_notification_manager.list_push_notification_configs(task_id)

    {
      task_id: task_id,
      configs: configs.map { |config| config.push_notification_config.to_h }
    }
  end

  ##
  # Handle tasks/pushNotificationConfig/delete method
  #
  # @param params [Hash] Method parameters
  # @param context [A2A::Server::Context] Request context
  # @return [Hash] Deletion result
  def handle_push_notification_config_delete(params, _context)
    validate_required_params(params, %w[taskId configId])

    task_id = params["taskId"]
    config_id = params["configId"]

    deleted = push_notification_manager.delete_push_notification_config(task_id, config_id)

    raise A2A::Errors::NotFound, "Push notification config not found" unless deleted

    {
      task_id: task_id,
      config_id: config_id,
      deleted: true
    }
  end

  ##
  # Handle agent/getCard method
  #
  # @param params [Hash] Method parameters
  # @param context [A2A::Server::Context] Request context
  # @return [Hash] Agent card
  def handle_agent_get_card(_params, context)
    # Generate agent card from registered capabilities
    card = generate_agent_card(context)

    {
      agent_card: card.to_h
    }
  end

  ##
  # Handle agent/getAuthenticatedExtendedCard method
  #
  # @param params [Hash] Method parameters
  # @param context [A2A::Server::Context] Request context
  # @return [Hash] Extended agent card
  def handle_agent_get_authenticated_extended_card(_params, context)
    # Verify authentication
    unless context.authenticated?
      raise A2A::Errors::AuthenticationRequired, "Authentication required for extended agent card"
    end

    # Generate extended agent card with authentication context
    card = generate_extended_agent_card(context)

    {
      agent_card: card.to_h
    }
  end

  ##
  # Get task manager instance
  #
  # @return [A2A::Server::TaskManager] Task manager
  def task_manager
    @task_manager ||= A2A::Server::TaskManager.new
  end

  ##
  # Get push notification manager instance
  #
  # @return [A2A::Server::PushNotificationManager] Push notification manager
  def push_notification_manager
    @push_notification_manager ||= A2A::Server::PushNotificationManager.new
  end

  protected

  ##
  # Process message synchronously (to be implemented by subclasses)
  #
  # @param message [A2A::Types::Message] The message to process
  # @param task [A2A::Types::Task] The associated task
  # @param context [A2A::Server::Context] Request context
  # @return [Object] Processing result
  def process_message_sync(message, task, context)
    raise NotImplementedError, "Subclasses must implement process_message_sync"
  end

  ##
  # Process message asynchronously (to be implemented by subclasses)
  #
  # @param message [A2A::Types::Message] The message to process
  # @param task [A2A::Types::Task] The associated task
  # @param context [A2A::Server::Context] Request context
  # @return [void]
  def process_message_async(message, task, context)
    raise NotImplementedError, "Subclasses must implement process_message_async"
  end

  ##
  # Process message stream (to be implemented by subclasses)
  #
  # @param message [A2A::Types::Message] The message to process
  # @param task [A2A::Types::Task] The associated task
  # @param context [A2A::Server::Context] Request context
  # @yield [response] Yields each response in the stream
  # @return [void]
  def process_message_stream(message, task, context)
    raise NotImplementedError, "Subclasses must implement process_message_stream"
  end

  ##
  # Generate agent card (to be implemented by subclasses)
  #
  # @param context [A2A::Server::Context] Request context
  # @return [A2A::Types::AgentCard] The agent card
  def generate_agent_card(context)
    raise NotImplementedError, "Subclasses must implement generate_agent_card"
  end

  ##
  # Generate extended agent card (to be implemented by subclasses)
  #
  # @param context [A2A::Server::Context] Request context
  # @return [A2A::Types::AgentCard] The extended agent card
  def generate_extended_agent_card(context)
    # Default implementation returns the same as regular card
    generate_agent_card(context)
  end

  private

  ##
  # Validate required parameters
  #
  # @param params [Hash] Parameters to validate
  # @param required [Array<String>] Required parameter names
  # @raise [A2A::Errors::InvalidParams] If required parameters are missing
  def validate_required_params(params, required)
    missing = required.reject { |param| params.key?(param) }

    return if missing.empty?

    raise A2A::Errors::InvalidParams, "Missing required parameters: #{missing.join(", ")}"
  end

  ##
  # Check if client is still connected (implementation specific)
  #
  # @param yielder [Object] The yielder object
  # @return [Boolean] True if client is connected
  def client_connected?(_yielder)
    # This is a placeholder - actual implementation depends on the server framework
    # For now, assume client is always connected
    true
  end
end
