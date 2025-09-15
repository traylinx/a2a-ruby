# frozen_string_literal: true

require "securerandom"
require_relative "storage"

##
# Manages task lifecycle, state transitions, and event processing
#
# The TaskManager is responsible for creating, updating, and managing tasks
# throughout their lifecycle. It handles state transitions, artifact management,
# message history, and event notifications.
#
module A2A
  module Server
    class TaskManager
      attr_reader :storage, :event_handlers, :config

      ##
      # Initialize a new TaskManager with performance optimizations
      #
      # @param storage [Object] Storage backend for task persistence
      # @param push_notification_manager [PushNotificationManager, nil] Push notification manager
      # @param config [Hash] Configuration options
      def initialize(storage: nil, push_notification_manager: nil, config: {})
        @storage = storage || A2A::Server::Storage::Memory.new
        @push_notification_manager = push_notification_manager
        @event_handlers = []
        @config = default_config.merge(config)
        @task_cache = {} # LRU cache for frequently accessed tasks
        @cache_mutex = Mutex.new
        @performance_metrics = {
          tasks_created: 0,
          tasks_updated: 0,
          cache_hits: 0,
          cache_misses: 0,
          avg_processing_time: 0.0
        }
        @metrics_mutex = Mutex.new
      end

      ##
      # Create a new task with performance tracking
      #
      # @param type [String] Task type identifier
      # @param params [Hash] Task parameters
      # @param context_id [String, nil] Optional context ID (generated if not provided)
      # @param metadata [Hash, nil] Optional task metadata
      # @return [A2A::Types::Task] The created task
      def create_task(type:, params: {}, context_id: nil, metadata: nil)
        A2A::Utils::Performance.profile("task_creation") do
          task_id = generate_task_id
          context_id ||= generate_context_id

          # Record task creation metric
          @metrics_mutex.synchronize { @performance_metrics[:tasks_created] += 1 }

          A2A::Monitoring.increment_counter("a2a_tasks_created", task_type: type) if defined?(A2A::Monitoring)
          A2A::Monitoring.log(:info, "Creating task", task_id: task_id, task_type: type) if defined?(A2A::Monitoring)

          task = A2A::Types::Task.new(
            id: task_id,
            context_id: context_id,
            status: A2A::Types::TaskStatus.new(
              state: A2A::Types::TASK_STATE_SUBMITTED,
              message: "Task created",
              updated_at: Time.now.utc.iso8601
            ),
            metadata: (metadata || {}).merge(
              type: type,
              params: params,
              created_at: Time.now.utc.iso8601
            )
          )

          @storage.save_task(task)

          # Cache the newly created task
          add_to_cache(task_id, task)

          # Emit task creation event
          emit_status_update_event(task)

          task
        end
      end

      ##
      # Get a task by ID with caching for performance
      #
      # @param task_id [String] The task ID
      # @param history_length [Integer, nil] Maximum number of history messages to include
      # @return [A2A::Types::Task] The task
      # @raise [A2A::Errors::TaskNotFound] If task doesn't exist
      def get_task(task_id, history_length: nil)
        start_time = Time.now

        # Check cache first for frequently accessed tasks
        cached_task = get_from_cache(task_id)
        if cached_task && (!history_length || !cached_task.history || cached_task.history.length <= history_length)
          record_cache_hit
          return cached_task
        end

        record_cache_miss
        task = @storage.get_task(task_id)
        raise A2A::Errors::TaskNotFound, "Task #{task_id} not found" unless task

        # Limit history if requested
        if history_length && task.history && task.history.length > history_length
          limited_history = task.history.last(history_length)
          # Create a new task instance with limited history
          task = A2A::Types::Task.new(
            id: task.id,
            context_id: task.context_id,
            status: task.status,
            artifacts: task.artifacts,
            history: limited_history,
            metadata: task.metadata
          )
        end

        # Cache the task for future access
        add_to_cache(task_id, task)

        record_processing_time(Time.now - start_time)
        task
      end

      ##
      # Update task status with performance tracking
      #
      # @param task_id [String] The task ID
      # @param status [A2A::Types::TaskStatus, Hash] New status
      # @param message [String, nil] Optional status message
      # @return [A2A::Types::Task] The updated task
      # @raise [A2A::Errors::TaskNotFound] If task doesn't exist
      def update_task_status(task_id, status, message: nil)
        A2A::Utils::Performance.profile("task_status_update") do
          task = get_task(task_id)

          # Validate state transition
          new_state = status.is_a?(A2A::Types::TaskStatus) ? status.state : status[:state] || status["state"]
          validate_state_transition(task.status.state, new_state)

          # Record task update metric
          @metrics_mutex.synchronize { @performance_metrics[:tasks_updated] += 1 }

          # Create new status
          new_status = if status.is_a?(A2A::Types::TaskStatus)
                         status
                       else
                         status_hash = status.dup
                         status_hash[:message] = message if message
                         status_hash[:updated_at] = Time.now.utc.iso8601
                         A2A::Types::TaskStatus.new(**status_hash)
                       end

          # Update task
          task.update_status(new_status)
          @storage.save_task(task)

          # Update cache
          add_to_cache(task_id, task)

          # Emit status update event
          emit_status_update_event(task)

          task
        end
      end

      ##
      # Cancel a task
      #
      # @param task_id [String] The task ID
      # @param reason [String, nil] Optional cancellation reason
      # @return [A2A::Types::Task] The canceled task
      # @raise [A2A::Errors::TaskNotFound] If task doesn't exist
      # @raise [A2A::Errors::TaskNotCancelable] If task cannot be canceled
      def cancel_task(task_id, reason: nil)
        task = get_task(task_id)

        unless task.cancelable?
          raise A2A::Errors::TaskNotCancelable,
                "Task #{task_id} in state '#{task.status.state}' cannot be canceled"
        end

        update_task_status(
          task_id,
          A2A::Types::TaskStatus.new(
            state: A2A::Types::TASK_STATE_CANCELED,
            message: reason || "Task canceled",
            updated_at: Time.now.utc.iso8601
          )
        )
      end

      ##
      # Add an artifact to a task
      #
      # @param task_id [String] The task ID
      # @param artifact [A2A::Types::Artifact] The artifact to add
      # @param append [Boolean] Whether to append to existing artifact with same ID
      # @return [A2A::Types::Task] The updated task
      # @raise [A2A::Errors::TaskNotFound] If task doesn't exist
      def add_artifact(task_id, artifact, append: false)
        task = get_task(task_id)

        if append && task.artifacts
          # Find existing artifact with same ID
          existing_artifact = task.artifacts.find { |a| a.artifact_id == artifact.artifact_id }
          if existing_artifact
            # Append parts to existing artifact
            artifact.parts.each { |part| existing_artifact.add_part(part) }
          else
            task.add_artifact(artifact)
          end
        else
          task.add_artifact(artifact)
        end

        @storage.save_task(task)

        # Emit artifact update event
        emit_artifact_update_event(task, artifact, append)

        task
      end

      ##
      # Add a message to task history
      #
      # @param task_id [String] The task ID
      # @param message [A2A::Types::Message] The message to add
      # @return [A2A::Types::Task] The updated task
      # @raise [A2A::Errors::TaskNotFound] If task doesn't exist
      def add_message(task_id, message)
        task = get_task(task_id)
        task.add_message(message)

        # Limit history length if configured
        if @config[:max_history_length] && task.history && task.history.length > @config[:max_history_length]
          # Keep only the most recent messages
          task.instance_variable_set(:@history, task.history.last(@config[:max_history_length]))
        end

        @storage.save_task(task)
        task
      end

      ##
      # List tasks by context ID
      #
      # @param context_id [String] The context ID
      # @return [Array<A2A::Types::Task>] Tasks in the context
      def list_tasks_by_context(*args)
        @storage.list_tasks_by_context(*args)
      end

      ##
      # Add an event handler
      #
      # @param handler [Proc] Event handler that receives (event_type, event_data)
      def add_event_handler(&handler)
        @event_handlers << handler
      end

      ##
      # Remove an event handler
      #
      # @param handler [Proc] The handler to remove
      def remove_event_handler(handler)
        @event_handlers.delete(handler)
      end

      private

      ##
      # Generate a unique task ID
      #
      # @return [String] A unique task ID
      def generate_task_id
        SecureRandom.uuid
      end

      ##
      # Generate a unique context ID
      #
      # @return [String] A unique context ID
      def generate_context_id
        SecureRandom.uuid
      end

      ##
      # Validate state transition
      #
      # @param current_state [String] Current task state
      # @param new_state [String] Proposed new state
      # @raise [ArgumentError] If transition is invalid
      def validate_state_transition(current_state, new_state)
        # Define valid state transitions
        valid_transitions = {
          A2A::Types::TASK_STATE_SUBMITTED => [
            A2A::Types::TASK_STATE_WORKING,
            A2A::Types::TASK_STATE_CANCELED,
            A2A::Types::TASK_STATE_REJECTED,
            A2A::Types::TASK_STATE_AUTH_REQUIRED
          ],
          A2A::Types::TASK_STATE_WORKING => [
            A2A::Types::TASK_STATE_INPUT_REQUIRED,
            A2A::Types::TASK_STATE_COMPLETED,
            A2A::Types::TASK_STATE_CANCELED,
            A2A::Types::TASK_STATE_FAILED,
            A2A::Types::TASK_STATE_AUTH_REQUIRED
          ],
          A2A::Types::TASK_STATE_INPUT_REQUIRED => [
            A2A::Types::TASK_STATE_WORKING,
            A2A::Types::TASK_STATE_COMPLETED,
            A2A::Types::TASK_STATE_CANCELED,
            A2A::Types::TASK_STATE_FAILED
          ],
          A2A::Types::TASK_STATE_AUTH_REQUIRED => [
            A2A::Types::TASK_STATE_WORKING,
            A2A::Types::TASK_STATE_CANCELED,
            A2A::Types::TASK_STATE_REJECTED
          ]
        }

        # Terminal states cannot transition
        terminal_states = [
          A2A::Types::TASK_STATE_COMPLETED,
          A2A::Types::TASK_STATE_CANCELED,
          A2A::Types::TASK_STATE_FAILED,
          A2A::Types::TASK_STATE_REJECTED,
          A2A::Types::TASK_STATE_UNKNOWN
        ]

        raise ArgumentError, "Cannot transition from terminal state '#{current_state}'" if terminal_states.include?(current_state)

        allowed_states = valid_transitions[current_state] || []
        return if allowed_states.include?(new_state)

        raise ArgumentError, "Invalid state transition from '#{current_state}' to '#{new_state}'"
      end

      ##
      # Emit a task status update event
      #
      # @param task [A2A::Types::Task] The task
      def emit_status_update_event(task)
        event = A2A::Types::TaskStatusUpdateEvent.new(
          task_id: task.id,
          context_id: task.context_id,
          status: task.status,
          metadata: {
            timestamp: Time.now.utc.iso8601,
            event_id: SecureRandom.uuid
          }
        )

        emit_event("task_status_update", event)

        # Send push notifications if manager is available
        @push_notification_manager&.notify_task_status_update(event)
      end

      ##
      # Emit a task artifact update event
      #
      # @param task [A2A::Types::Task] The task
      # @param artifact [A2A::Types::Artifact] The artifact
      # @param append [Boolean] Whether this was an append operation
      def emit_artifact_update_event(task, artifact, append)
        event = A2A::Types::TaskArtifactUpdateEvent.new(
          task_id: task.id,
          context_id: task.context_id,
          artifact: artifact,
          append: append,
          metadata: {
            timestamp: Time.now.utc.iso8601,
            event_id: SecureRandom.uuid
          }
        )

        emit_event("task_artifact_update", event)

        # Send push notifications if manager is available
        @push_notification_manager&.notify_task_artifact_update(event)
      end

      ##
      # Emit an event to all registered handlers
      #
      # @param event_type [String] The event type
      # @param event_data [Object] The event data
      def emit_event(event_type, event_data)
        @event_handlers.each do |handler|
          handler.call(event_type, event_data)
        rescue StandardError => e
          # Log error but don't fail the operation
          warn "Error in event handler: #{e.message}"
        end
      end

      ##
      # Default configuration
      #
      # @return [Hash] Default configuration
      def default_config
        {
          max_history_length: 100,
          cache_size: 1000,
          cache_ttl: 300 # 5 minutes
        }
      end

      ##
      # Get task from cache
      #
      # @param task_id [String] The task ID
      # @return [A2A::Types::Task, nil] Cached task or nil
      def get_from_cache(task_id)
        @cache_mutex.synchronize do
          entry = @task_cache[task_id]
          return nil unless entry

          # Check TTL
          if Time.now - entry[:timestamp] > @config[:cache_ttl]
            @task_cache.delete(task_id)
            return nil
          end

          entry[:task]
        end
      end

      ##
      # Add task to cache with LRU eviction
      #
      # @param task_id [String] The task ID
      # @param task [A2A::Types::Task] The task to cache
      def add_to_cache(task_id, task)
        @cache_mutex.synchronize do
          # Evict oldest entries if cache is full
          if @task_cache.size >= @config[:cache_size]
            oldest_key = @task_cache.min_by { |_, entry| entry[:timestamp] }.first
            @task_cache.delete(oldest_key)
          end

          @task_cache[task_id] = {
            task: task,
            timestamp: Time.now
          }
        end
      end

      ##
      # Clear task cache
      #
      def clear_cache!
        @cache_mutex.synchronize { @task_cache.clear }
      end

      ##
      # Record cache hit
      #
      def record_cache_hit
        @metrics_mutex.synchronize { @performance_metrics[:cache_hits] += 1 }
      end

      ##
      # Record cache miss
      #
      def record_cache_miss
        @metrics_mutex.synchronize { @performance_metrics[:cache_misses] += 1 }
      end

      ##
      # Record processing time
      #
      # @param duration [Float] Processing time in seconds
      def record_processing_time(duration)
        @metrics_mutex.synchronize do
          current_avg = @performance_metrics[:avg_processing_time]
          total_ops = @performance_metrics[:tasks_created] + @performance_metrics[:tasks_updated]

          @performance_metrics[:avg_processing_time] = if total_ops.positive?
                                                         ((current_avg * (total_ops - 1)) + duration) / total_ops
                                                       else
                                                         duration
                                                       end
        end
      end

      ##
      # Get performance metrics
      #
      # @return [Hash] Performance metrics
      def performance_metrics
        @metrics_mutex.synchronize { @performance_metrics.dup }
      end

      ##
      # Reset performance metrics
      #
      def reset_performance_metrics!
        @metrics_mutex.synchronize do
          @performance_metrics = {
            tasks_created: 0,
            tasks_updated: 0,
            cache_hits: 0,
            cache_misses: 0,
            avg_processing_time: 0.0
          }
        end
      end
    end
  end
end
