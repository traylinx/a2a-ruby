# frozen_string_literal: true

require "spec_helper"

RSpec.describe A2A::Server::Events::EventQueue do
  describe A2A::Server::Events::Event do
    let(:task) { A2A::Types::Task.new(id: "task-1", context_id: "ctx-1", status: A2A::Types::TaskStatus.new(state: "submitted")) }
    let(:event) { described_class.new(type: "task", data: task) }

    describe "#initialize" do
      it "creates an event with required attributes" do
        expect(event.type).to eq("task")
        expect(event.data).to eq(task)
        expect(event.timestamp).to be_a(Time)
        expect(event.id).to be_a(String)
      end

      it "accepts a custom ID" do
        custom_event = described_class.new(type: "task", data: task, id: "custom-id")
        expect(custom_event.id).to eq("custom-id")
      end
    end

    describe "#task_event?" do
      it "returns true for task-related events" do
        expect(described_class.new(type: "task", data: task).task_event?).to be true
        expect(described_class.new(type: "task_status_update", data: task).task_event?).to be true
        expect(described_class.new(type: "task_artifact_update", data: task).task_event?).to be true
      end

      it "returns false for non-task events" do
        expect(described_class.new(type: "message", data: task).task_event?).to be false
      end
    end

    describe "#message_event?" do
      it "returns true for message events" do
        expect(described_class.new(type: "message", data: task).message_event?).to be true
      end

      it "returns false for non-message events" do
        expect(described_class.new(type: "task", data: task).message_event?).to be false
      end
    end

    describe "#task_id" do
      it "extracts task ID from Task objects" do
        expect(event.task_id).to eq("task-1")
      end

      it "returns nil for non-task data" do
        message_event = described_class.new(type: "message", data: "some data")
        expect(message_event.task_id).to be_nil
      end
    end

    describe "#to_h" do
      it "converts event to hash" do
        hash = event.to_h
        expect(hash[:type]).to eq("task")
        expect(hash[:data]).to be_a(Hash)
        expect(hash[:timestamp]).to be_a(String)
        expect(hash[:id]).to be_a(String)
      end
    end
  end

  describe A2A::Server::Events::InMemoryEventQueue do
    let(:queue) { described_class.new }
    let(:event) { A2A::Server::Events::Event.new(type: "test", data: { message: "hello" }) }

    after { queue.close }

    describe "#publish" do
      it "publishes events to subscribers" do
        received_events = []
        
        # Start subscriber in a thread
        subscriber_thread = Thread.new do
          queue.subscribe { |e| received_events << e }
        end

        # Give subscriber time to start and register
        sleep 0.05

        # Publish event
        queue.publish(event)

        # Give more time for event to be processed
        sleep 0.05

        expect(received_events).to include(event)
        
        subscriber_thread.kill
        subscriber_thread.join(0.1) # Wait for thread to finish
      end

      it "does not publish to closed queue" do
        queue.close
        expect { queue.publish(event) }.not_to raise_error
      end
    end

    describe "#subscribe" do
      it "returns an enumerator when no block given" do
        enumerator = queue.subscribe
        expect(enumerator).to be_a(Enumerator)
      end

      it "filters events when filter provided" do
        received_events = []
        filter = ->(e) { e.type == "test" }
        
        subscriber_thread = Thread.new do
          queue.subscribe(filter) { |e| received_events << e }
        end

        # Give subscriber time to start and register
        sleep 0.05

        # Publish matching event
        queue.publish(event)
        
        # Publish non-matching event
        other_event = A2A::Server::Events::Event.new(type: "other", data: {})
        queue.publish(other_event)

        # Give more time for events to be processed
        sleep 0.05

        expect(received_events).to include(event)
        expect(received_events).not_to include(other_event)
        
        subscriber_thread.kill
        subscriber_thread.join(0.1) # Wait for thread to finish
      end
    end

    describe "#close" do
      it "closes the queue" do
        queue.close
        expect(queue.closed?).to be true
      end
    end

    describe "#subscriber_count" do
      it "tracks number of subscribers" do
        expect(queue.subscriber_count).to eq(0)
        
        thread = Thread.new { queue.subscribe { |_| } }
        sleep 0.01
        
        expect(queue.subscriber_count).to eq(1)
        
        thread.kill
        sleep 0.01
        
        expect(queue.subscriber_count).to eq(0)
      end
    end
  end
end