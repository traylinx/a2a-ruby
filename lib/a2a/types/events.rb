# frozen_string_literal: true

module A2A::Types
  ##
  # Represents a task status update event
  #
  # These events are sent when a task's status changes, allowing clients
  # to track task progress in real-time.
  #
  class TaskStatusUpdateEvent < BaseModel
    attr_reader :task_id, :context_id, :status, :metadata

    ##
    # Initialize a new task status update event
    #
    # @param task_id [String] The task identifier
    # @param context_id [String] The context identifier
    # @param status [TaskStatus, Hash] The new task status
    # @param metadata [Hash, nil] Additional event metadata
    def initialize(task_id:, context_id:, status:, metadata: nil)
      @task_id = task_id
      @context_id = context_id
      @status = status.is_a?(TaskStatus) ? status : TaskStatus.from_h(status)
      @metadata = metadata

      validate!
    end

    ##
    # Get the event type
    #
    # @return [String] The event type
    def event_type
      "task_status_update"
    end

    ##
    # Check if this is a terminal status update
    #
    # @return [Boolean] True if the status is terminal
    def terminal?
      @status.state.in?(%w[completed canceled failed rejected])
    end

    private

    def validate!
      validate_required(:task_id, :context_id, :status)
      validate_type(:task_id, String)
      validate_type(:context_id, String)
      validate_type(:status, TaskStatus)
    end
  end

  ##
  # Represents a task artifact update event
  #
  # These events are sent when artifacts are added or updated for a task,
  # supporting streaming artifact delivery.
  #
  class TaskArtifactUpdateEvent < BaseModel
    attr_reader :task_id, :context_id, :artifact, :append, :metadata

    ##
    # Initialize a new task artifact update event
    #
    # @param task_id [String] The task identifier
    # @param context_id [String] The context identifier
    # @param artifact [Artifact, Hash] The artifact being updated
    # @param append [Boolean] Whether to append to existing artifact
    # @param metadata [Hash, nil] Additional event metadata
    def initialize(task_id:, context_id:, artifact:, append: false, metadata: nil)
      @task_id = task_id
      @context_id = context_id
      @artifact = artifact.is_a?(Artifact) ? artifact : Artifact.from_h(artifact)
      @append = append
      @metadata = metadata

      validate!
    end

    ##
    # Get the event type
    #
    # @return [String] The event type
    def event_type
      "task_artifact_update"
    end

    ##
    # Check if this is an append operation
    #
    # @return [Boolean] True if appending to existing artifact
    def append?
      @append
    end

    ##
    # Check if this is a replace operation
    #
    # @return [Boolean] True if replacing existing artifact
    def replace?
      !@append
    end

    private

    def validate!
      validate_required(:task_id, :context_id, :artifact)
      validate_type(:task_id, String)
      validate_type(:context_id, String)
      validate_type(:artifact, Artifact)
    end
  end
end
