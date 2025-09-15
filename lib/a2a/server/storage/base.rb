# frozen_string_literal: true

module A2A
  module Server
    module Storage
    end
  end
end

##
# Abstract base class for task storage backends
#
# This class defines the interface that all storage backends must implement
# for task persistence and retrieval.
#
class A2A::Server::Storage::Base
  ##
  # Save a task to storage
  #
  # @param task [A2A::Types::Task] The task to save
  # @return [void]
  # @raise [NotImplementedError] Must be implemented by subclasses
  def save_task(task)
    raise NotImplementedError, "#{self.class} must implement #save_task"
  end

  ##
  # Get a task by ID
  #
  # @param task_id [String] The task ID
  # @return [A2A::Types::Task, nil] The task or nil if not found
  # @raise [NotImplementedError] Must be implemented by subclasses
  def get_task(task_id)
    raise NotImplementedError, "#{self.class} must implement #get_task"
  end

  ##
  # Delete a task by ID
  #
  # @param task_id [String] The task ID
  # @return [Boolean] True if task was deleted, false if not found
  # @raise [NotImplementedError] Must be implemented by subclasses
  def delete_task(task_id)
    raise NotImplementedError, "#{self.class} must implement #delete_task"
  end

  ##
  # List all tasks for a given context ID
  #
  # @param context_id [String] The context ID
  # @return [Array<A2A::Types::Task>] Tasks in the context
  # @raise [NotImplementedError] Must be implemented by subclasses
  def list_tasks_by_context(context_id)
    raise NotImplementedError, "#{self.class} must implement #list_tasks_by_context"
  end

  ##
  # List all tasks
  #
  # @return [Array<A2A::Types::Task>] All tasks
  # @raise [NotImplementedError] Must be implemented by subclasses
  def list_all_tasks
    raise NotImplementedError, "#{self.class} must implement #list_all_tasks"
  end

  ##
  # Check if a task exists
  #
  # @param task_id [String] The task ID
  # @return [Boolean] True if task exists
  def task_exists?(task_id)
    !get_task(task_id).nil?
  end

  ##
  # Clear all tasks (useful for testing)
  #
  # @return [void]
  # @raise [NotImplementedError] Must be implemented by subclasses
  def clear_all_tasks
    raise NotImplementedError, "#{self.class} must implement #clear_all_tasks"
  end

  ##
  # Save a push notification config
  #
  # @param config [A2A::Types::TaskPushNotificationConfig] The config to save
  # @return [void]
  # @raise [NotImplementedError] Must be implemented by subclasses
  def save_push_notification_config(config)
    raise NotImplementedError, "#{self.class} must implement #save_push_notification_config"
  end

  ##
  # Get a push notification config by task and config ID
  #
  # @param task_id [String] The task ID
  # @param config_id [String] The config ID
  # @return [A2A::Types::TaskPushNotificationConfig, nil] The config or nil if not found
  # @raise [NotImplementedError] Must be implemented by subclasses
  def get_push_notification_config_by_id(task_id, config_id)
    raise NotImplementedError, "#{self.class} must implement #get_push_notification_config_by_id"
  end

  ##
  # List all push notification configs for a task
  #
  # @param task_id [String] The task ID
  # @return [Array<A2A::Types::TaskPushNotificationConfig>] List of configs
  # @raise [NotImplementedError] Must be implemented by subclasses
  def list_push_notification_configs(task_id)
    raise NotImplementedError, "#{self.class} must implement #list_push_notification_configs"
  end

  ##
  # Delete a push notification config
  #
  # @param task_id [String] The task ID
  # @param config_id [String] The config ID
  # @return [Boolean] True if deleted, false if not found
  # @raise [NotImplementedError] Must be implemented by subclasses
  def delete_push_notification_config(task_id, config_id)
    raise NotImplementedError, "#{self.class} must implement #delete_push_notification_config"
  end
end
