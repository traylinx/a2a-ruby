# frozen_string_literal: true

begin
  require "redis"
  require "json"
rescue LoadError
  # Redis is optional - only load if available
end

##
# Redis storage backend for tasks
#
# This storage backend persists tasks to Redis using JSON serialization.
# It's suitable for distributed deployments and provides good performance
# for task storage and retrieval.
#
class A2A::Server::Storage::Redis < Base
  # Redis key prefixes
  TASK_KEY_PREFIX = "a2a:task:"
  CONTEXT_KEY_PREFIX = "a2a:context:"
  TASK_LIST_KEY = "a2a:tasks:all"

  ##
  # Initialize the Redis storage
  #
  # @param redis [Redis, nil] Redis client instance
  # @param url [String, nil] Redis URL (if redis client not provided)
  # @param namespace [String] Key namespace prefix
  # @param ttl [Integer, nil] Optional TTL for task keys (in seconds)
  # @raise [LoadError] If Redis gem is not available
  def initialize(redis: nil, url: nil, namespace: "a2a", ttl: nil)
    raise LoadError, "Redis gem is required for Redis storage. Add 'redis' to your Gemfile." unless defined?(::Redis)

    @redis = redis || ::Redis.new(url: url || ENV["REDIS_URL"] || "redis://localhost:6379")
    @namespace = namespace
    @ttl = ttl
  end

  ##
  # Save a task to Redis
  #
  # @param task [A2A::Types::Task] The task to save
  # @return [void]
  def save_task(task)
    task_key = build_task_key(task.id)
    context_key = build_context_key(task.context_id)
    task_data = serialize_task(task)

    @redis.multi do |multi|
      # Store the task data
      multi.set(task_key, task_data)

      # Add to context set
      multi.sadd(context_key, task.id)

      # Add to global task list
      multi.sadd(TASK_LIST_KEY, task.id)

      # Set TTL if configured
      if @ttl
        multi.expire(task_key, @ttl)
        multi.expire(context_key, @ttl)
      end
    end
  end

  ##
  # Get a task by ID
  #
  # @param task_id [String] The task ID
  # @return [A2A::Types::Task, nil] The task or nil if not found
  def get_task(task_id)
    task_key = build_task_key(task_id)
    task_data = @redis.get(task_key)

    return nil unless task_data

    deserialize_task(task_data)
  end

  ##
  # Delete a task by ID
  #
  # @param task_id [String] The task ID
  # @return [Boolean] True if task was deleted, false if not found
  def delete_task(task_id)
    task = get_task(task_id)
    return false unless task

    task_key = build_task_key(task_id)
    context_key = build_context_key(task.context_id)

    @redis.multi do |multi|
      # Remove task data
      multi.del(task_key)

      # Remove from context set
      multi.srem(context_key, task_id)

      # Remove from global task list
      multi.srem(TASK_LIST_KEY, task_id)
    end

    true
  end

  ##
  # List all tasks for a given context ID
  #
  # @param context_id [String] The context ID
  # @return [Array<A2A::Types::Task>] Tasks in the context
  def list_tasks_by_context(context_id)
    context_key = build_context_key(context_id)
    task_ids = @redis.smembers(context_key)

    return [] if task_ids.empty?

    # Get all tasks in a single pipeline
    task_keys = task_ids.map { |id| build_task_key(id) }
    task_data_list = @redis.mget(*task_keys)

    tasks = task_data_list.compact.map { |data| deserialize_task(data) }

    # Sort by creation time (from metadata)
    tasks.sort_by { |task| task.metadata&.dig("created_at") || "" }
  end

  ##
  # List all tasks
  #
  # @return [Array<A2A::Types::Task>] All tasks
  def list_all_tasks
    task_ids = @redis.smembers(TASK_LIST_KEY)

    return [] if task_ids.empty?

    # Get all tasks in a single pipeline
    task_keys = task_ids.map { |id| build_task_key(id) }
    task_data_list = @redis.mget(*task_keys)

    tasks = task_data_list.compact.map { |data| deserialize_task(data) }

    # Sort by creation time (from metadata)
    tasks.sort_by { |task| task.metadata&.dig("created_at") || "" }
  end

  ##
  # Clear all tasks
  #
  # @return [void]
  def clear_all_tasks
    # Get all task IDs
    task_ids = @redis.smembers(TASK_LIST_KEY)

    return if task_ids.empty?

    # Build all keys to delete
    task_keys = task_ids.map { |id| build_task_key(id) }

    # Get all context IDs to clean up context sets
    tasks = task_keys.filter_map { |key| @redis.get(key) }.map { |data| deserialize_task(data) }
    context_keys = tasks.map { |task| build_context_key(task.context_id) }.uniq

    # Delete everything in a transaction
    @redis.multi do |multi|
      # Delete all task data
      multi.del(*task_keys) unless task_keys.empty?

      # Delete all context sets
      multi.del(*context_keys) unless context_keys.empty?

      # Clear the global task list
      multi.del(TASK_LIST_KEY)
    end
  end

  ##
  # Get the number of stored tasks
  #
  # @return [Integer] Number of tasks
  def task_count
    @redis.scard(TASK_LIST_KEY)
  end

  ##
  # Check Redis connection
  #
  # @return [Boolean] True if connected
  def connected?
    @redis.ping == "PONG"
  rescue ::Redis::BaseError
    false
  end

  ##
  # Get Redis info
  #
  # @return [Hash] Redis server info
  delegate :info, to: :@redis

  ##
  # Flush all A2A data from Redis (dangerous!)
  #
  # This removes all A2A-related keys from Redis.
  # Use with caution in production.
  #
  # @return [void]
  def flush_all_a2a_data!
    pattern = "#{@namespace}:*"
    keys = @redis.keys(pattern)

    return if keys.empty?

    @redis.del(*keys)
  end

  private

  ##
  # Build a Redis key for a task
  #
  # @param task_id [String] The task ID
  # @return [String] Redis key
  def build_task_key(task_id)
    "#{@namespace}:#{TASK_KEY_PREFIX}#{task_id}"
  end

  ##
  # Build a Redis key for a context set
  #
  # @param context_id [String] The context ID
  # @return [String] Redis key
  def build_context_key(context_id)
    "#{@namespace}:#{CONTEXT_KEY_PREFIX}#{context_id}"
  end

  ##
  # Serialize a task to JSON for Redis storage
  #
  # @param task [A2A::Types::Task] The task to serialize
  # @return [String] JSON string
  def serialize_task(task)
    JSON.generate(task.to_h)
  end

  ##
  # Deserialize a task from JSON
  #
  # @param task_data [String] JSON string
  # @return [A2A::Types::Task] The deserialized task
  def deserialize_task(task_data)
    data = JSON.parse(task_data)
    A2A::Types::Task.from_h(data)
  end
end
