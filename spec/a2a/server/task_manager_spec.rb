# frozen_string_literal: true

require "spec_helper"

RSpec.describe A2A::Server::TaskManager do
  let(:storage) { A2A::Server::Storage::Memory.new }
  let(:task_manager) { described_class.new(storage: storage) }

  describe "#initialize" do
    it "creates a task manager with default storage" do
      manager = described_class.new
      expect(manager.storage).to be_a(A2A::Server::Storage::Memory)
    end

    it "creates a task manager with custom storage" do
      expect(task_manager.storage).to eq(storage)
    end

    it "initializes with default config" do
      expect(task_manager.config[:max_history_length]).to eq(100)
    end
  end

  describe "#create_task" do
    it "creates a task with required fields" do
      task = task_manager.create_task(type: "test_task", params: { key: "value" })

      expect(task).to be_a(A2A::Types::Task)
      expect(task.id).to be_a(String)
      expect(task.context_id).to be_a(String)
      expect(task.status.state).to eq(A2A::Types::TASK_STATE_SUBMITTED)
      expect(task.metadata[:type]).to eq("test_task")
      expect(task.metadata[:params]).to eq({ key: "value" })
    end

    it "uses provided context_id" do
      context_id = "custom-context"
      task = task_manager.create_task(type: "test_task", context_id: context_id)

      expect(task.context_id).to eq(context_id)
    end

    it "saves task to storage" do
      task = task_manager.create_task(type: "test_task")
      stored_task = storage.get_task(task.id)

      expect(stored_task).to eq(task)
    end

    it "emits status update event" do
      events = []
      task_manager.add_event_handler { |type, data| events << [type, data] }

      task = task_manager.create_task(type: "test_task")

      expect(events.length).to eq(1)
      expect(events[0][0]).to eq("task_status_update")
      expect(events[0][1]).to be_a(A2A::Types::TaskStatusUpdateEvent)
      expect(events[0][1].task_id).to eq(task.id)
    end
  end

  describe "#get_task" do
    let(:task) { task_manager.create_task(type: "test_task") }

    it "retrieves existing task" do
      retrieved_task = task_manager.get_task(task.id)
      expect(retrieved_task.id).to eq(task.id)
    end

    it "raises error for non-existent task" do
      expect do
        task_manager.get_task("non-existent")
      end.to raise_error(A2A::Errors::TaskNotFound)
    end

    context "with history length limit" do
      before do
        # Add multiple messages to history
        5.times do |i|
          message = A2A::Types::Message.new(
            message_id: "msg-#{i}",
            role: "user",
            parts: [A2A::Types::TextPart.new(text: "Message #{i}")]
          )
          task_manager.add_message(task.id, message)
        end
      end

      it "limits history when requested" do
        retrieved_task = task_manager.get_task(task.id, history_length: 3)
        expect(retrieved_task.history.length).to eq(3)
      end

      it "returns all history when no limit specified" do
        retrieved_task = task_manager.get_task(task.id)
        expect(retrieved_task.history.length).to eq(5)
      end
    end
  end

  describe "#update_task_status" do
    let(:task) { task_manager.create_task(type: "test_task") }

    it "updates task status" do
      new_status = A2A::Types::TaskStatus.new(
        state: A2A::Types::TASK_STATE_WORKING,
        message: "Task is now working"
      )

      updated_task = task_manager.update_task_status(task.id, new_status)

      expect(updated_task.status.state).to eq(A2A::Types::TASK_STATE_WORKING)
      expect(updated_task.status.message).to eq("Task is now working")
    end

    it "updates task status from hash" do
      updated_task = task_manager.update_task_status(
        task.id,
        { state: A2A::Types::TASK_STATE_WORKING },
        message: "Working on it"
      )

      expect(updated_task.status.state).to eq(A2A::Types::TASK_STATE_WORKING)
      expect(updated_task.status.message).to eq("Working on it")
    end

    it "validates state transitions" do
      # First transition to working
      task_manager.update_task_status(task.id, { state: A2A::Types::TASK_STATE_WORKING })

      # Then complete the task
      task_manager.update_task_status(task.id, { state: A2A::Types::TASK_STATE_COMPLETED })

      # Try to transition from completed (should fail)
      expect do
        task_manager.update_task_status(task.id, { state: A2A::Types::TASK_STATE_WORKING })
      end.to raise_error(ArgumentError, /Cannot transition from terminal state/)
    end

    it "emits status update event" do
      # Ensure task is created first
      task_id = task.id
      
      events = []
      task_manager.add_event_handler { |type, data| events << [type, data] }

      task_manager.update_task_status(task_id, { state: A2A::Types::TASK_STATE_WORKING })

      expect(events.length).to eq(1)
      expect(events[0][0]).to eq("task_status_update")
      expect(events[0][1].status.state).to eq(A2A::Types::TASK_STATE_WORKING)
    end
  end

  describe "#cancel_task" do
    let(:task) { task_manager.create_task(type: "test_task") }

    it "cancels a cancelable task" do
      canceled_task = task_manager.cancel_task(task.id, reason: "User requested")

      expect(canceled_task.status.state).to eq(A2A::Types::TASK_STATE_CANCELED)
      expect(canceled_task.status.message).to eq("User requested")
    end

    it "raises error for non-cancelable task" do
      # Complete the task first (need to go through valid state transitions)
      task_manager.update_task_status(task.id, { state: A2A::Types::TASK_STATE_WORKING })
      task_manager.update_task_status(task.id, { state: A2A::Types::TASK_STATE_COMPLETED })

      expect do
        task_manager.cancel_task(task.id)
      end.to raise_error(A2A::Errors::TaskNotCancelable)
    end
  end

  describe "#add_artifact" do
    let(:task) { task_manager.create_task(type: "test_task") }
    let(:artifact) do
      A2A::Types::Artifact.new(
        artifact_id: "test-artifact",
        parts: [A2A::Types::TextPart.new(text: "Test content")]
      )
    end

    it "adds artifact to task" do
      updated_task = task_manager.add_artifact(task.id, artifact)

      expect(updated_task.artifacts.length).to eq(1)
      expect(updated_task.artifacts.first.artifact_id).to eq("test-artifact")
    end

    it "appends to existing artifact when requested" do
      # Add initial artifact
      task_manager.add_artifact(task.id, artifact)

      # Add another part to the same artifact
      additional_artifact = A2A::Types::Artifact.new(
        artifact_id: "test-artifact",
        parts: [A2A::Types::TextPart.new(text: "Additional content")]
      )

      updated_task = task_manager.add_artifact(task.id, additional_artifact, append: true)

      expect(updated_task.artifacts.length).to eq(1)
      expect(updated_task.artifacts.first.parts.length).to eq(2)
    end

    it "emits artifact update event" do
      events = []
      task_manager.add_event_handler { |type, data| events << [type, data] }

      # Clear creation event
      events.clear

      task_manager.add_artifact(task.id, artifact)

      artifact_events = events.select { |event| event[0] == "task_artifact_update" }
      expect(artifact_events.length).to eq(1)
      expect(artifact_events[0][1]).to be_a(A2A::Types::TaskArtifactUpdateEvent)
      expect(artifact_events[0][1].artifact.artifact_id).to eq("test-artifact")
    end
  end

  describe "#add_message" do
    let(:task) { task_manager.create_task(type: "test_task") }
    let(:message) do
      A2A::Types::Message.new(
        message_id: "test-message",
        role: "user",
        parts: [A2A::Types::TextPart.new(text: "Hello")]
      )
    end

    it "adds message to task history" do
      updated_task = task_manager.add_message(task.id, message)

      expect(updated_task.history.length).to eq(1)
      expect(updated_task.history.first.message_id).to eq("test-message")
    end

    it "limits history length when configured" do
      # Configure smaller history limit
      task_manager.instance_variable_set(:@config, { max_history_length: 2 })

      # Add 3 messages
      3.times do |i|
        msg = A2A::Types::Message.new(
          message_id: "msg-#{i}",
          role: "user",
          parts: [A2A::Types::TextPart.new(text: "Message #{i}")]
        )
        task_manager.add_message(task.id, msg)
      end

      updated_task = task_manager.get_task(task.id)
      expect(updated_task.history.length).to eq(2)
      expect(updated_task.history.first.message_id).to eq("msg-1")
      expect(updated_task.history.last.message_id).to eq("msg-2")
    end
  end

  describe "#list_tasks_by_context" do
    let(:context_id) { "test-context" }

    before do
      # Create tasks with same context
      2.times { |_i| task_manager.create_task(type: "test_task", context_id: context_id) }
      # Create task with different context
      task_manager.create_task(type: "other_task", context_id: "other-context")
    end

    it "returns tasks for specified context" do
      tasks = task_manager.list_tasks_by_context(context_id)
      expect(tasks.length).to eq(2)
      expect(tasks.all? { |t| t.context_id == context_id }).to be true
    end
  end

  describe "event handling" do
    it "allows adding and removing event handlers" do
      handler1_calls = []
      handler2_calls = []

      handler1 = proc { |type, data| handler1_calls << [type, data] }
      handler2 = proc { |type, data| handler2_calls << [type, data] }

      task_manager.add_event_handler(&handler1)
      task_manager.add_event_handler(&handler2)

      task_manager.create_task(type: "test_task")

      expect(handler1_calls.length).to eq(1)
      expect(handler2_calls.length).to eq(1)

      # Remove one handler
      task_manager.remove_event_handler(handler1)

      task_manager.create_task(type: "test_task")

      expect(handler1_calls.length).to eq(1) # No new calls
      expect(handler2_calls.length).to eq(2) # One new call
    end

    it "handles errors in event handlers gracefully" do
      # Add a handler that raises an error
      task_manager.add_event_handler { |_type, _data| raise "Handler error" }

      # This should not raise an error
      expect do
        task_manager.create_task(type: "test_task")
      end.not_to raise_error
    end
  end

  describe "state transition validation" do
    let(:task) { task_manager.create_task(type: "test_task") }

    it "allows valid transitions from submitted" do
      valid_states = [
        A2A::Types::TASK_STATE_WORKING,
        A2A::Types::TASK_STATE_CANCELED,
        A2A::Types::TASK_STATE_REJECTED,
        A2A::Types::TASK_STATE_AUTH_REQUIRED
      ]

      valid_states.each do |state|
        new_task = task_manager.create_task(type: "test_task")
        expect do
          task_manager.update_task_status(new_task.id, { state: state })
        end.not_to raise_error
      end
    end

    it "prevents invalid transitions" do
      expect do
        task_manager.update_task_status(task.id, { state: A2A::Types::TASK_STATE_COMPLETED })
      end.to raise_error(ArgumentError, /Invalid state transition/)
    end

    it "prevents transitions from terminal states" do
      # Complete the task
      task_manager.update_task_status(task.id, { state: A2A::Types::TASK_STATE_WORKING })
      task_manager.update_task_status(task.id, { state: A2A::Types::TASK_STATE_COMPLETED })

      # Try to transition from completed
      expect do
        task_manager.update_task_status(task.id, { state: A2A::Types::TASK_STATE_WORKING })
      end.to raise_error(ArgumentError, /Cannot transition from terminal state/)
    end
  end
end
