# frozen_string_literal: true

##
# <%= model_class_name("task") %>
#
# ActiveRecord model for A2A tasks with JSON serialization and validation.
# This model provides persistence for A2A task data including status, artifacts,
# and message history.
#
class <%= model_class_name("task") %> < ApplicationRecord
  self.table_name = "<%= tasks_table_name %>"
  self.primary_key = "id"

  # Associations
  has_many :<%= model_file_name("push_notification_config").pluralize %>, 
           foreign_key: :task_id, 
           dependent: :destroy,
           class_name: "<%= model_class_name("push_notification_config") %>"

  # Validations
  validates :id, presence: true, uniqueness: true
  validates :context_id, presence: true
  validates :kind, presence: true, inclusion: { in: %w[task] }
  validates :status_state, presence: true, inclusion: { 
    in: %w[submitted working input-required completed canceled failed rejected auth-required unknown] 
  }

  # Scopes
  scope :active, -> { where(deleted_at: nil) }
  scope :by_status, ->(status) { where(status_state: status) }
  scope :by_context, ->(context_id) { where(context_id: context_id) }
  scope :by_type, ->(type) { where(type: type) }
  scope :recent, -> { order(created_at: :desc) }
  scope :processing, -> { where(status_state: %w[submitted working]) }
  scope :completed, -> { where(status_state: %w[completed canceled failed rejected]) }

  # Callbacks
  before_create :ensure_id
  before_save :update_status_timestamp
  after_update :notify_status_change, if: :saved_change_to_status_state?

  # Soft delete
  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  # Status management
  def status
    A2A::Types::TaskStatus.new(
      state: status_state,
      message: status_message,
      progress: status_progress,
      result: status_result,
      error: status_error,
      updated_at: status_updated_at&.iso8601
    )
  end

  def status=(new_status)
    if new_status.is_a?(A2A::Types::TaskStatus)
      self.status_state = new_status.state
      self.status_message = new_status.message
      self.status_progress = new_status.progress
      self.status_result = new_status.result
      self.status_error = new_status.error
      self.status_updated_at = Time.current
    elsif new_status.is_a?(Hash)
      self.status = A2A::Types::TaskStatus.from_h(new_status)
    else
      raise ArgumentError, "Status must be TaskStatus or Hash"
    end
  end

  # Artifact management
  def artifacts_objects
    return [] unless artifacts.present?
    
    artifacts.map { |artifact_data| A2A::Types::Artifact.from_h(artifact_data) }
  end

  def add_artifact(artifact)
    artifact_data = artifact.is_a?(A2A::Types::Artifact) ? artifact.to_h : artifact
    
    self.artifacts = (artifacts || []) + [artifact_data]
    save!
  end

  def update_artifact(artifact_id, new_artifact, append: false)
    return unless artifacts.present?
    
    artifact_index = artifacts.find_index { |a| a["artifact_id"] == artifact_id }
    return unless artifact_index
    
    new_artifact_data = new_artifact.is_a?(A2A::Types::Artifact) ? new_artifact.to_h : new_artifact
    
    if append && artifacts[artifact_index]["parts"].present?
      # Append parts to existing artifact
      existing_parts = artifacts[artifact_index]["parts"] || []
      new_parts = new_artifact_data["parts"] || []
      artifacts[artifact_index]["parts"] = existing_parts + new_parts
    else
      # Replace entire artifact
      artifacts[artifact_index] = new_artifact_data
    end
    
    save!
  end

  # Message history management
  def history_objects
    return [] unless history.present?
    
    history.map { |message_data| A2A::Types::Message.from_h(message_data) }
  end

  def add_message(message)
    message_data = message.is_a?(A2A::Types::Message) ? message.to_h : message
    
    self.history = (history || []) + [message_data]
    
    # Limit history length if configured
    max_history = A2A.config.max_history_length || 100
    if history.length > max_history
      self.history = history.last(max_history)
    end
    
    save!
  end

  # Convert to A2A::Types::Task
  def to_a2a_task
    A2A::Types::Task.new(
      id: id,
      context_id: context_id,
      kind: kind,
      status: status,
      artifacts: artifacts_objects,
      history: history_objects,
      metadata: metadata || {}
    )
  end

  # Create from A2A::Types::Task
  def self.from_a2a_task(task)
    new(
      id: task.id,
      context_id: task.context_id,
      kind: task.kind,
      status_state: task.status.state,
      status_message: task.status.message,
      status_progress: task.status.progress,
      status_result: task.status.result,
      status_error: task.status.error,
      status_updated_at: task.status.updated_at ? Time.parse(task.status.updated_at) : Time.current,
      artifacts: task.artifacts&.map(&:to_h),
      history: task.history&.map(&:to_h),
      metadata: task.metadata
    )
  end

  # Search and filtering
  def self.search(query)
    return all if query.blank?
    
    where(
      "status_message ILIKE ? OR metadata::text ILIKE ?", 
      "%#{query}%", "%#{query}%"
    )
  end

  def self.by_metadata(key, value)
    <% if postgresql? %>
    where("metadata->? = ?", key, value.to_json)
    <% else %>
    where("JSON_EXTRACT(metadata, ?) = ?", "$.#{key}", value.to_s)
    <% end %>
  end

  private

  def ensure_id
    self.id ||= SecureRandom.uuid
    self.context_id ||= SecureRandom.uuid
  end

  def update_status_timestamp
    if status_state_changed?
      self.status_updated_at = Time.current
    end
  end

  def notify_status_change
    # Trigger push notifications and events
    A2A::Server::TaskManager.instance.notify_task_status_change(self) if A2A.config.push_notifications_enabled
  end
end