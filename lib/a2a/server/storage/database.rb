# frozen_string_literal: true

begin
  require "active_record"
rescue LoadError
  # ActiveRecord is optional - only load if available
end

module A2A
  module Server
    module Storage
    end
  end
end

# Only define the class if ActiveRecord is available
if defined?(ActiveRecord)
  ##
  # Database storage backend for tasks using ActiveRecord
  #
  # This storage backend persists tasks to a database using ActiveRecord.
  # It requires ActiveRecord to be available and properly configured.
  #
  module A2A
    module Server
      module Storage
        class Database < A2A::Server::Storage::Base
          ##
          # ActiveRecord model for task persistence
          #
          class TaskRecord < (defined?(ApplicationRecord) ? ApplicationRecord : ActiveRecord::Base)
            self.table_name = "a2a_tasks"

            validates :task_id, presence: true, uniqueness: true
            validates :context_id, presence: true
            validates :task_data, presence: true

            # Serialize task data as JSON
            serialize :task_data, coder: JSON

            # Indexes for efficient querying
            # These should be created in a migration:
            # add_index :a2a_tasks, :task_id, unique: true
            # add_index :a2a_tasks, :context_id
            # add_index :a2a_tasks, :created_at
            # add_index :a2a_tasks, :updated_at
          end

          ##
          # Initialize the database storage
          #
          # @param connection [ActiveRecord::Base, nil] Optional AR connection
          # @raise [LoadError] If ActiveRecord is not available
          def initialize(connection: nil)
            unless defined?(ActiveRecord)
              raise LoadError, "ActiveRecord is required for database storage. Add 'activerecord' to your Gemfile."
            end

            @connection = connection || ActiveRecord::Base
            ensure_table_exists!
          end

          ##
          # Save a task to the database
          #
          # @param task [A2A::Types::Task] The task to save
          # @return [void]
          def save_task(task)
            task_data = serialize_task(task)

            record = TaskRecord.find_or_initialize_by(task_id: task.id)
            record.assign_attributes(
              context_id: task.context_id,
              task_data: task_data,
              updated_at: Time.now
            )

            record.created_at = Time.now if record.new_record?

            record.save!
          end

          ##
          # Get a task by ID
          #
          # @param task_id [String] The task ID
          # @return [A2A::Types::Task, nil] The task or nil if not found
          def get_task(task_id)
            record = TaskRecord.find_by(task_id: task_id)
            return nil unless record

            deserialize_task(record.task_data)
          end

          ##
          # Delete a task by ID
          #
          # @param task_id [String] The task ID
          # @return [Boolean] True if task was deleted, false if not found
          def delete_task(task_id)
            deleted_count = TaskRecord.where(task_id: task_id).delete_all
            deleted_count.positive?
          end

          ##
          # List all tasks for a given context ID
          #
          # @param context_id [String] The context ID
          # @return [Array<A2A::Types::Task>] Tasks in the context
          def list_tasks_by_context(context_id)
            records = TaskRecord.where(context_id: context_id).order(:created_at)
            records.map { |record| deserialize_task(record.task_data) }
          end

          ##
          # List all tasks
          #
          # @return [Array<A2A::Types::Task>] All tasks
          def list_all_tasks
            records = TaskRecord.order(:created_at)
            records.map { |record| deserialize_task(record.task_data) }
          end

          ##
          # List tasks with optional filtering
          #
          # @param filters [Hash] Optional filters (state, context_id, etc.)
          # @return [Array<A2A::Types::Task>] Filtered tasks
          def list_tasks(**filters)
            query = build_base_query(filters)
            tasks = query.map { |record| deserialize_task(record.task_data) }

            apply_post_query_filters(tasks, filters)
          end

          ##
          # Clear all tasks
          #
          # @return [void]
          def clear_all_tasks
            TaskRecord.delete_all
          end

          ##
          # Get the number of stored tasks
          #
          # @return [Integer] Number of tasks
          def task_count
            TaskRecord.count
          end

          ##
          # Create the tasks table if it doesn't exist
          #
          # This is a convenience method for development/testing.
          # In production, use proper migrations.
          #
          # @return [void]
          def create_table!
            return if table_exists?

            @connection.connection.create_table :a2a_tasks, force: true do |t|
              t.string :task_id, null: false, limit: 255
              t.string :context_id, null: false, limit: 255
              t.text :task_data, null: false
              t.timestamps null: false

              t.index :task_id, unique: true
              t.index :context_id
              t.index :created_at
              t.index :updated_at
            end
          end

          ##
          # Drop the tasks table
          #
          # @return [void]
          def drop_table!
            @connection.connection.drop_table :a2a_tasks if table_exists?
          end

          ##
          # Check if the tasks table exists
          #
          # @return [Boolean] True if table exists
          def table_exists?
            @connection.connection.table_exists?(:a2a_tasks)
          end

          ##
          # Ensure the tasks table exists
          #
          # @return [void]
          def ensure_table_exists!
            return if table_exists?

            warn "A2A tasks table does not exist. Creating it automatically."
            warn "In production, you should create this table using a proper migration."
            create_table!
          end

          ##
          # Serialize a task to a hash for database storage
          #
          # @param task [A2A::Types::Task] The task to serialize
          # @return [Hash] Serialized task data
          def serialize_task(task)
            task.to_h
          end

          ##
          # Deserialize a task from database storage
          #
          # @param task_data [Hash] Serialized task data
          # @return [A2A::Types::Task] The deserialized task
          def deserialize_task(task_data)
            A2A::Types::Task.from_h(task_data)
          end

          private

          def build_base_query(filters)
            query = TaskRecord.order(:created_at)
            query = query.where(context_id: filters[:context_id]) if filters[:context_id]
            query
          end

          def apply_post_query_filters(tasks, filters)
            tasks = tasks.select { |task| task.status&.state == filters[:state] } if filters[:state]
            apply_metadata_filters(tasks, filters)
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
end
