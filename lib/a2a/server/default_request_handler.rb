# frozen_string_literal: true

require_relative "request_handler"
require_relative "agent_execution/agent_executor"
require_relative "agent_execution/request_context"
require_relative "events/event_queue"
require_relative "events/event_consumer"
require_relative "task_manager"
require_relative "push_notification_manager"

module A2A
  module Server
    ##
    # Default implementation of the RequestHandler interface
    #
    # This class provides a complete implementation of the A2A request handler
    # that uses an AgentExecutor for processing requests and manages tasks
    # through a TaskManager. It mirrors the Python DefaultRequestHandler.
    #
    class DefaultRequestHandler < RequestHandler
      attr_reader :agent_executor, :task_manager, :push_notification_manager, :task_store

      ##
      # Initialize the default request handler
      #
      # @param agent_executor [AgentExecution::AgentExecutor] The agent executor for processing requests
      # @param task_store [Object, nil] Optional task store for persistence
      # @param push_notification_manager [PushNotificationManager, nil] Optional push notification manager
      def initialize(agent_executor, task_store: nil, push_notification_manager: nil)
        @agent_executor = agent_executor
        @task_store = task_store
        @task_manager = TaskManager.new(
          storage: task_store,
          push_notification_manager: push_notification_manager
        )
        @push_notification_manager = push_notification_manager || PushNotificationManager.new
      end

      ##
      # Handle the 'tasks/get' method
      #
      # @param params [Hash] Parameters with task ID and optional history length
      # @param context [A2A::Server::Context, nil] Server context
      # @return [A2A::Types::Task, nil] The task if found
      def on_get_task(params, _context = nil)
        task_id = params["id"] || params[:id]
        history_length = params["historyLength"] || params[:history_length]

        raise A2A::Errors::InvalidParams, "Task ID is required" unless task_id

        @task_manager.get_task(task_id, history_length: history_length)
      rescue A2A::Errors::TaskNotFound
        nil
      end

      ##
      # Handle the 'tasks/cancel' method
      #
      # @param params [Hash] Parameters with task ID
      # @param context [A2A::Server::Context, nil] Server context
      # @return [A2A::Types::Task, nil] The canceled task if found
      def on_cancel_task(params, context = nil)
        task_id = params["id"] || params[:id]
        params["reason"] || params[:reason]

        raise A2A::Errors::InvalidParams, "Task ID is required" unless task_id

        # Create request context for cancellation
        request_context = AgentExecution::RequestContextBuilder.from_task_operation(
          params, context, operation: "cancel"
        )

        # Create event queue for the cancellation
        event_queue = Events::InMemoryEventQueue.new

        # Set up event processing
        setup_event_processing(event_queue, task_id, request_context.context_id)

        begin
          # Execute cancellation through agent executor
          @agent_executor.cancel(request_context, event_queue)

          # Wait briefly for the cancellation to be processed
          sleep 0.1

          # Return the updated task
          @task_manager.get_task(task_id)
        rescue A2A::Errors::TaskNotFound
          nil
        ensure
          event_queue.close
        end
      end

      ##
      # Handle the 'message/send' method (non-streaming)
      #
      # @param params [Hash] Parameters with message and configuration
      # @param context [A2A::Server::Context, nil] Server context
      # @return [A2A::Types::Task, A2A::Types::Message] The result task or message
      def on_message_send(params, context = nil)
        # Build request context
        request_context = AgentExecution::RequestContextBuilder.from_message_send(params, context)

        # Create event queue for execution
        event_queue = Events::InMemoryEventQueue.new
        result = nil

        # Set up event processing to capture the final result
        setup_event_processing(event_queue, request_context.task_id, request_context.context_id) do |event|
          case event.type
          when "task"
            result = event.data if event.data.status.state == A2A::Types::TASK_STATE_COMPLETED
          when "message"
            result = event.data
          end
        end

        begin
          # Execute through agent executor
          @agent_executor.execute(request_context, event_queue)

          # Wait for completion (with timeout)
          timeout = 30 # 30 seconds timeout
          start_time = Time.now

          sleep 0.1 while result.nil? && (Time.now - start_time) < timeout

          raise A2A::Errors::Timeout, "Request timed out" unless result

          result
        ensure
          event_queue.close
        end
      end

      ##
      # Handle the 'message/stream' method (streaming)
      #
      # @param params [Hash] Parameters with message and configuration
      # @param context [A2A::Server::Context, nil] Server context
      # @return [Enumerator] Enumerator yielding events
      def on_message_send_stream(params, context = nil)
        # Build request context
        request_context = AgentExecution::RequestContextBuilder.from_streaming_message(params, context)

        # Create event queue for execution
        event_queue = Events::InMemoryEventQueue.new

        Enumerator.new do |yielder|
          # Set up event processing to yield events
          setup_event_processing(event_queue, request_context.task_id, request_context.context_id) do |event|
            yielder << event.data
          end

          begin
            # Execute through agent executor
            @agent_executor.execute(request_context, event_queue)

            # Keep the stream alive until the task completes
            loop do
              sleep 0.1

              # Check if task is complete
              next unless request_context.task_id

              begin
                task = @task_manager.get_task(request_context.task_id)
                break if task&.completed?
              rescue A2A::Errors::TaskNotFound
                break
              end
            end
          ensure
            event_queue.close
          end
        end
      end

      ##
      # Handle the 'tasks/resubscribe' method
      #
      # @param params [Hash] Parameters with task ID
      # @param context [A2A::Server::Context, nil] Server context
      # @return [Enumerator] Enumerator yielding events
      def on_resubscribe_to_task(params, _context = nil)
        task_id = params["id"] || params[:id]
        raise A2A::Errors::InvalidParams, "Task ID is required" unless task_id

        # Verify task exists
        task = @task_manager.get_task(task_id)
        raise A2A::Errors::TaskNotFound, "Task #{task_id} not found" unless task

        # Create event queue for resubscription
        event_queue = Events::InMemoryEventQueue.new

        Enumerator.new do |yielder|
          # Send current task state immediately
          yielder << task

          # Set up event processing for future updates
          setup_event_processing(event_queue, task_id, task.context_id) do |event|
            yielder << event.data
          end

          begin
            # Keep the stream alive
            loop do
              sleep 1

              # Check if task is still active
              begin
                current_task = @task_manager.get_task(task_id)
                break if current_task&.completed?
              rescue A2A::Errors::TaskNotFound
                break
              end
            end
          ensure
            event_queue.close
          end
        end
      end

      ##
      # Handle push notification config operations
      #
      # @param params [Hash] Parameters with task ID and config
      # @param context [A2A::Server::Context, nil] Server context
      # @return [A2A::Types::TaskPushNotificationConfig] The config
      def on_set_task_push_notification_config(params, _context = nil)
        task_id = params["taskId"] || params[:task_id]
        config_data = params["config"] || params[:config]

        raise A2A::Errors::InvalidParams, "Task ID is required" unless task_id
        raise A2A::Errors::InvalidParams, "Config is required" unless config_data

        # Verify task exists
        @task_manager.get_task(task_id)

        @push_notification_manager.set_push_notification_config(task_id, config_data)
      end

      ##
      # Get push notification config
      #
      # @param params [Hash] Parameters with task ID and optional config ID
      # @param context [A2A::Server::Context, nil] Server context
      # @return [A2A::Types::TaskPushNotificationConfig] The config
      def on_get_task_push_notification_config(params, _context = nil)
        task_id = params["taskId"] || params[:task_id]
        config_id = params["configId"] || params[:config_id]

        raise A2A::Errors::InvalidParams, "Task ID is required" unless task_id

        config = @push_notification_manager.get_push_notification_config(task_id, config_id: config_id)
        raise A2A::Errors::NotFound, "Push notification config not found" unless config

        config
      end

      ##
      # List push notification configs
      #
      # @param params [Hash] Parameters with task ID
      # @param context [A2A::Server::Context, nil] Server context
      # @return [Array<A2A::Types::TaskPushNotificationConfig>] The configs
      def on_list_task_push_notification_config(params, _context = nil)
        task_id = params["taskId"] || params[:task_id]
        raise A2A::Errors::InvalidParams, "Task ID is required" unless task_id

        @push_notification_manager.list_push_notification_configs(task_id)
      end

      ##
      # Delete push notification config
      #
      # @param params [Hash] Parameters with task ID and config ID
      # @param context [A2A::Server::Context, nil] Server context
      def on_delete_task_push_notification_config(params, _context = nil)
        task_id = params["taskId"] || params[:task_id]
        config_id = params["configId"] || params[:config_id]

        raise A2A::Errors::InvalidParams, "Task ID and config ID are required" unless task_id && config_id

        deleted = @push_notification_manager.delete_push_notification_config(task_id, config_id)
        raise A2A::Errors::NotFound, "Push notification config not found" unless deleted
      end

      private

      ##
      # Set up event processing for a task
      #
      # @param event_queue [Events::EventQueue] The event queue
      # @param task_id [String, nil] The task ID to filter events for
      # @param context_id [String, nil] The context ID to filter events for
      # @yield [event] Block to process each event
      def setup_event_processing(event_queue, task_id, context_id, &block)
        # Create event consumer
        consumer = Events::EventConsumer.new(event_queue)

        # Register handlers for different event types
        consumer.register_handler("task") do |event|
          # Update task manager with task events
          @task_manager.storage.save_task(event.data) if @task_manager.storage.respond_to?(:save_task)
          block&.call(event)
        end

        consumer.register_handler("task_status_update") do |event|
          # Update task status
          @task_manager.update_task_status(
            event.data.task_id,
            event.data.status
          )
          block&.call(event)
        end

        consumer.register_handler("task_artifact_update") do |event|
          # Add artifact to task
          @task_manager.add_artifact(
            event.data.task_id,
            event.data.artifact,
            append: event.data.append
          )
          block&.call(event)
        end

        consumer.register_handler("message") do |event|
          # Add message to task history if we have a task
          @task_manager.add_message(task_id, event.data) if task_id
          block&.call(event)
        end

        # Start consuming events
        filter = if task_id || context_id
                   lambda { |event|
                     (task_id.nil? || event.task_id == task_id) &&
                       (context_id.nil? || event.context_id == context_id)
                   }
                 else
                   nil
                 end

        consumer.start(filter)
        consumer
      end
    end
  end
end
