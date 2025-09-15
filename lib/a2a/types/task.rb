# frozen_string_literal: true

module A2A::Types
  ##
  # Represents a task in the A2A protocol
  #
  # A task represents a unit of work that can be executed by an agent.
  # It includes status information, artifacts, message history, and metadata.
  #
  class Task < A2A::Types::BaseModel
    attr_reader :id, :context_id, :kind, :status, :artifacts, :history, :metadata

    ##
    # Initialize a new task
    #
    # @param id [String] Unique task identifier
    # @param context_id [String] Context identifier for grouping related tasks
    # @param status [TaskStatus, Hash] Current task status
    # @param kind [String] Task kind (always "task")
    # @param artifacts [Array<Artifact>, nil] Task artifacts
    # @param history [Array<Message>, nil] Message history
    # @param metadata [Hash, nil] Additional metadata
    def initialize(id:, context_id:, status:, kind: KIND_TASK, artifacts: nil, history: nil, metadata: nil)
      @id = id
      @context_id = context_id
      @kind = kind
      @status = status.is_a?(TaskStatus) ? status : TaskStatus.from_h(status)
      @artifacts = artifacts&.map { |a| a.is_a?(Artifact) ? a : Artifact.from_h(a) }
      @history = history&.map { |m| m.is_a?(Message) ? m : Message.from_h(m) }
      @metadata = metadata

      validate!
    end

    ##
    # Add an artifact to the task
    #
    # @param artifact [Artifact] The artifact to add
    def add_artifact(artifact)
      @artifacts ||= []
      @artifacts << artifact
    end

    ##
    # Add a message to the history
    #
    # @param message [Message] The message to add
    def add_message(message)
      @history ||= []
      @history << message
    end

    ##
    # Update the task status
    #
    # @param new_status [TaskStatus, Hash] The new status
    def update_status(new_status)
      @status = new_status.is_a?(TaskStatus) ? new_status : TaskStatus.from_h(new_status)
    end

    ##
    # Check if the task is in a terminal state
    #
    # @return [Boolean] True if the task is completed, canceled, failed, or rejected
    def terminal?
      %w[completed canceled failed rejected].include?(@status.state)
    end

    ##
    # Check if the task can be canceled
    #
    # @return [Boolean] True if the task can be canceled
    def cancelable?
      %w[submitted working input-required].include?(@status.state)
    end

    private

    def validate!
      validate_required(:id, :context_id, :status, :kind)
      validate_inclusion(:kind, [KIND_TASK])
      validate_type(:status, TaskStatus)
      validate_array_type(:artifacts, Artifact) if @artifacts
      validate_array_type(:history, Message) if @history
    end
  end

  ##
  # Represents the status of a task
  #
  class TaskStatus < A2A::Types::BaseModel
    attr_reader :state, :message, :progress, :result, :error, :updated_at

    ##
    # Initialize a new task status
    #
    # @param state [String] The current state
    # @param message [String, nil] Optional status message
    # @param progress [Float, nil] Progress percentage (0.0 to 1.0)
    # @param result [Object, nil] Task result (for completed tasks)
    # @param error [Hash, nil] Error information (for failed tasks)
    # @param updated_at [String, nil] ISO 8601 timestamp of last update
    def initialize(state:, message: nil, progress: nil, result: nil, error: nil, updated_at: nil)
      @state = state
      @message = message
      @progress = progress
      @result = result
      @error = error
      @updated_at = updated_at || Time.now.utc.iso8601

      validate!
    end

    ##
    # Check if the status indicates success
    #
    # @return [Boolean] True if the task completed successfully
    def success?
      @state == TASK_STATE_COMPLETED && @error.nil?
    end

    ##
    # Check if the status indicates failure
    #
    # @return [Boolean] True if the task failed
    def failure?
      @state == TASK_STATE_FAILED || !@error.nil?
    end

    ##
    # Check if the task is still active
    #
    # @return [Boolean] True if the task is still being processed
    def active?
      %w[submitted working input-required].include?(@state)
    end

    private

    def validate!
      validate_required(:state, :updated_at)
      validate_inclusion(:state, VALID_TASK_STATES)

      return unless @progress

      validate_type(:progress, Numeric)
      return if @progress.between?(0.0, 1.0)

      raise ArgumentError, "progress must be between 0.0 and 1.0"
    end
  end
end
