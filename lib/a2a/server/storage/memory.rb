# frozen_string_literal: true

##
# In-memory storage backend for tasks
#
# This storage backend keeps all tasks in memory using a simple hash.
# It's suitable for development, testing, and single-process deployments
# where persistence across restarts is not required.
#
module A2A
  module Server
    module Storage
      class Memory < A2A::Server::Storage::Base
        ##
        # Initialize the memory storage with performance optimizations
        def initialize
          @tasks = {}
          @push_configs = {}
          @context_index = {} # Index for faster context-based lookups
          @mutex = Mutex.new
          @stats = {
            reads: 0,
            writes: 0,
            cache_hits: 0,
            cache_misses: 0
          }
        end

        ##
        # Save a task to memory with context indexing
        #
        # @param task [A2A::Types::Task] The task to save
        # @return [void]
        def save_task(task)
          @mutex.synchronize do
            @tasks[task.id] = task

            # Update context index for faster lookups
            @context_index[task.context_id] ||= []
            @context_index[task.context_id] << task.id unless @context_index[task.context_id].include?(task.id)

            @stats[:writes] += 1
          end
        end

        ##
        # Get a task by ID with performance tracking
        #
        # @param task_id [String] The task ID
        # @return [A2A::Types::Task, nil] The task or nil if not found
        def get_task(task_id)
          @mutex.synchronize do
            @stats[:reads] += 1
            task = @tasks[task_id]
            if task
              @stats[:cache_hits] += 1
            else
              @stats[:cache_misses] += 1
            end
            task
          end
        end

        ##
        # Delete a task by ID
        #
        # @param task_id [String] The task ID
        # @return [Boolean] True if task was deleted, false if not found
        def delete_task(task_id)
          @mutex.synchronize do
            !@tasks.delete(task_id).nil?
          end
        end

        ##
        # List all tasks for a given context ID using optimized index
        #
        # @param context_id [String] The context ID
        # @return [Array<A2A::Types::Task>] Tasks in the context
        def list_tasks_by_context(context_id)
          @mutex.synchronize do
            @stats[:reads] += 1

            # Use context index for faster lookups
            task_ids = @context_index[context_id] || []
            tasks = task_ids.filter_map { |id| @tasks[id] }

            if tasks.any?
              @stats[:cache_hits] += 1
            else
              @stats[:cache_misses] += 1
            end

            tasks
          end
        end

        ##
        # List all tasks
        #
        # @return [Array<A2A::Types::Task>] All tasks
        def list_all_tasks
          @mutex.synchronize do
            @tasks.values.dup
          end
        end

        ##
        # List tasks with optional filtering
        #
        # @param filters [Hash] Optional filters (state, context_id, etc.)
        # @return [Array<A2A::Types::Task>] Filtered tasks
        def list_tasks(**filters)
          @mutex.synchronize do
            @stats[:reads] += 1
            tasks = @tasks.values

            tasks = apply_basic_filters(tasks, filters)
            tasks = apply_metadata_filters(tasks, filters)

            tasks.dup
          end
        end

        ##
        # Clear all tasks
        #
        # @return [void]
        def clear_all_tasks
          @mutex.synchronize do
            @tasks.clear
          end
        end

        ##
        # Get the number of stored tasks
        #
        # @return [Integer] Number of tasks
        def task_count
          @mutex.synchronize do
            @tasks.size
          end
        end

        ##
        # Save a push notification config
        #
        # @param config [A2A::Types::TaskPushNotificationConfig] The config to save
        # @return [void]
        def save_push_notification_config(config)
          @mutex.synchronize do
            @push_configs[config.task_id] ||= {}
            @push_configs[config.task_id][config.push_notification_config.id] = config
          end
        end

        ##
        # Get a push notification config by task and config ID
        #
        # @param task_id [String] The task ID
        # @param config_id [String] The config ID
        # @return [A2A::Types::TaskPushNotificationConfig, nil] The config or nil if not found
        def get_push_notification_config_by_id(task_id, config_id)
          @mutex.synchronize do
            @push_configs.dig(task_id, config_id)
          end
        end

        ##
        # List all push notification configs for a task
        #
        # @param task_id [String] The task ID
        # @return [Array<A2A::Types::TaskPushNotificationConfig>] List of configs
        def list_push_notification_configs(task_id)
          @mutex.synchronize do
            (@push_configs[task_id] || {}).values
          end
        end

        ##
        # Delete a push notification config
        #
        # @param task_id [String] The task ID
        # @param config_id [String] The config ID
        # @return [Boolean] True if deleted, false if not found
        def delete_push_notification_config(task_id, config_id)
          @mutex.synchronize do
            task_configs = @push_configs[task_id]
            return false unless task_configs

            deleted = !task_configs.delete(config_id).nil?

            # Clean up empty task entries
            @push_configs.delete(task_id) if task_configs.empty?

            deleted
          end
        end

        ##
        # Get storage performance statistics
        #
        # @return [Hash] Performance statistics
        def performance_stats
          @mutex.synchronize { @stats.dup }
        end

        ##
        # Reset performance statistics
        #
        def reset_performance_stats!
          @mutex.synchronize do
            @stats = {
              reads: 0,
              writes: 0,
              cache_hits: 0,
              cache_misses: 0
            }
          end
        end

        ##
        # Get cache hit ratio
        #
        # @return [Float] Cache hit ratio (0.0 to 1.0)
        def cache_hit_ratio
          @mutex.synchronize do
            total_reads = @stats[:cache_hits] + @stats[:cache_misses]
            return 0.0 if total_reads.zero?

            @stats[:cache_hits].to_f / total_reads
          end
        end

        private

        def apply_basic_filters(tasks, filters)
          tasks = tasks.select { |task| task.status&.state == filters[:state] } if filters[:state]
          tasks = tasks.select { |task| task.context_id == filters[:context_id] } if filters[:context_id]
          tasks
        end

        def apply_metadata_filters(tasks, filters)
          filters.each do |key, value|
            next if %i[state context_id].include?(key)

            tasks = tasks.select { |task| apply_single_filter(task, key, value) }
          end
          tasks
        end

        def apply_single_filter(task, key, value)
          case key
          when :task_type
            task.metadata&.dig(:type) == value || task.metadata&.dig("type") == value
          when :created_after
            created_at = get_created_at(task)
            created_at && Time.parse(created_at) > value
          when :created_before
            created_at = get_created_at(task)
            created_at && Time.parse(created_at) < value
          else
            # Generic metadata filter
            task.metadata&.dig(key) == value || task.metadata&.dig(key.to_s) == value
          end
        end

        def get_created_at(task)
          task.metadata&.dig(:created_at) || task.metadata&.dig("created_at")
        end
      end
    end
  end
end
