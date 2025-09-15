# frozen_string_literal: true

require_relative "request_context"
require_relative "../events/event_queue"

module A2A
  module Server
    module AgentExecution
      ##
      # Abstract base class for agent executors
      #
      # Agent executors contain the core logic of the agent, executing tasks based on
      # requests and publishing updates to an event queue. This mirrors the Python
      # AgentExecutor interface.
      #
      class AgentExecutor
        ##
        # Execute the agent's logic for a given request context
        #
        # The agent should read necessary information from the context and
        # publish Task or Message events, or TaskStatusUpdateEvent/TaskArtifactUpdateEvent
        # to the event_queue. This method should return once the agent's execution
        # for this request is complete or yields control (e.g., enters an input-required state).
        #
        # @param context [RequestContext] The request context containing the message, task ID, etc.
        # @param event_queue [A2A::Server::Events::EventQueue] The queue to publish events to
        # @abstract Subclasses must implement this method
        def execute(context, event_queue)
          raise NotImplementedError, "Subclasses must implement execute"
        end

        ##
        # Request the agent to cancel an ongoing task
        #
        # The agent should attempt to stop the task identified by the task_id
        # in the context and publish a TaskStatusUpdateEvent with state 'canceled'
        # to the event_queue.
        #
        # @param context [RequestContext] The request context containing the task ID to cancel
        # @param event_queue [A2A::Server::Events::EventQueue] The queue to publish the cancellation status update to
        # @abstract Subclasses must implement this method
        def cancel(context, event_queue)
          raise NotImplementedError, "Subclasses must implement cancel"
        end

        protected

        ##
        # Helper method to publish a task status update event
        #
        # @param event_queue [A2A::Server::Events::EventQueue] The event queue
        # @param task_id [String] The task ID
        # @param context_id [String] The context ID
        # @param status [A2A::Types::TaskStatus] The new task status
        # @param metadata [Hash, nil] Optional metadata
        def publish_task_status_update(event_queue, task_id, context_id, status, metadata = nil)
          event_data = A2A::Types::TaskStatusUpdateEvent.new(
            task_id: task_id,
            context_id: context_id,
            status: status,
            metadata: metadata
          )

          event = A2A::Server::Events::Event.new(
            type: "task_status_update",
            data: event_data
          )

          event_queue.publish(event)
        end

        ##
        # Helper method to publish a task artifact update event
        #
        # @param event_queue [A2A::Server::Events::EventQueue] The event queue
        # @param task_id [String] The task ID
        # @param context_id [String] The context ID
        # @param artifact [A2A::Types::Artifact] The artifact
        # @param append [Boolean] Whether this is an append operation
        # @param metadata [Hash, nil] Optional metadata
        def publish_task_artifact_update(event_queue, task_id, context_id, artifact, append = false, metadata = nil)
          event_data = A2A::Types::TaskArtifactUpdateEvent.new(
            task_id: task_id,
            context_id: context_id,
            artifact: artifact,
            append: append,
            metadata: metadata
          )

          event = A2A::Server::Events::Event.new(
            type: "task_artifact_update",
            data: event_data
          )

          event_queue.publish(event)
        end

        ##
        # Helper method to publish a task object
        #
        # @param event_queue [A2A::Server::Events::EventQueue] The event queue
        # @param task [A2A::Types::Task] The task object
        def publish_task(event_queue, task)
          event = A2A::Server::Events::Event.new(
            type: "task",
            data: task
          )

          event_queue.publish(event)
        end

        ##
        # Helper method to publish a message object
        #
        # @param event_queue [A2A::Server::Events::EventQueue] The event queue
        # @param message [A2A::Types::Message] The message object
        def publish_message(event_queue, message)
          event = A2A::Server::Events::Event.new(
            type: "message",
            data: message
          )

          event_queue.publish(event)
        end
      end

      ##
      # Simple agent executor implementation
      #
      # A basic implementation that can be used as a starting point for custom agents.
      # Provides default behavior for task creation and status management.
      #
      class SimpleAgentExecutor < AgentExecutor
        def initialize(agent_card: nil, task_manager: nil)
          @agent_card = agent_card
          @task_manager = task_manager
        end

        ##
        # Execute a request by creating a task and processing the message
        #
        # @param context [RequestContext] The request context
        # @param event_queue [A2A::Server::Events::EventQueue] The event queue
        def execute(context, event_queue)
          # Create or get the task
          task = ensure_task(context)
          publish_task(event_queue, task)

          # Update task to working state
          working_status = A2A::Types::TaskStatus.new(
            state: A2A::Types::TASK_STATE_WORKING,
            message: "Processing request",
            updated_at: Time.now.utc.iso8601
          )

          publish_task_status_update(
            event_queue,
            task.id,
            task.context_id,
            working_status
          )

          # Process the message (delegate to subclass)
          result = process_message(context.message, task, context)

          # Update task with result
          completed_status = A2A::Types::TaskStatus.new(
            state: A2A::Types::TASK_STATE_COMPLETED,
            result: result,
            updated_at: Time.now.utc.iso8601
          )

          publish_task_status_update(
            event_queue,
            task.id,
            task.context_id,
            completed_status
          )
        rescue StandardError => e
          # Handle errors by updating task status
          if task
            error_status = A2A::Types::TaskStatus.new(
              state: A2A::Types::TASK_STATE_FAILED,
              error: { message: e.message, type: e.class.name },
              updated_at: Time.now.utc.iso8601
            )

            publish_task_status_update(
              event_queue,
              task.id,
              task.context_id,
              error_status
            )
          end

          raise
        end

        ##
        # Cancel a task by updating its status
        #
        # @param context [RequestContext] The request context
        # @param event_queue [A2A::Server::Events::EventQueue] The event queue
        def cancel(context, event_queue)
          task_id = context.task_id
          return unless task_id

          canceled_status = A2A::Types::TaskStatus.new(
            state: A2A::Types::TASK_STATE_CANCELED,
            message: "Task canceled by request",
            updated_at: Time.now.utc.iso8601
          )

          publish_task_status_update(
            event_queue,
            task_id,
            context.context_id,
            canceled_status
          )
        end

        protected

        ##
        # Process a message (to be implemented by subclasses)
        #
        # @param message [A2A::Types::Message] The message to process
        # @param task [A2A::Types::Task] The associated task
        # @param context [RequestContext] The request context
        # @return [Object] Processing result
        def process_message(message, _task, _context)
          # Default implementation just echoes the message
          {
            echo: message.to_h,
            processed_at: Time.now.utc.iso8601
          }
        end

        private

        ##
        # Ensure a task exists for the request context
        #
        # @param context [RequestContext] The request context
        # @return [A2A::Types::Task] The task object
        def ensure_task(context)
          if context.task_id && @task_manager
            # Try to get existing task
            existing_task = begin
              @task_manager.get_task(context.task_id)
            rescue StandardError
              nil
            end
            return existing_task if existing_task
          end

          # Create new task
          task_id = context.task_id || SecureRandom.uuid
          context_id = context.context_id || SecureRandom.uuid

          A2A::Types::Task.new(
            id: task_id,
            context_id: context_id,
            status: A2A::Types::TaskStatus.new(
              state: A2A::Types::TASK_STATE_SUBMITTED,
              message: "Task created",
              updated_at: Time.now.utc.iso8601
            ),
            history: context.message ? [context.message] : [],
            metadata: {
              created_at: Time.now.utc.iso8601,
              executor: self.class.name
            }
          )
        end
      end
    end
  end
end
