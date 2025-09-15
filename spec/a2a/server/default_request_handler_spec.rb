# frozen_string_literal: true

require "spec_helper"

RSpec.describe A2A::Server::DefaultRequestHandler do
  let(:agent_executor) { instance_double(A2A::Server::AgentExecution::AgentExecutor) }
  let(:handler) { described_class.new(agent_executor) }

  describe "#initialize" do
    it "creates a handler with required components" do
      expect(handler.agent_executor).to eq(agent_executor)
      expect(handler.task_manager).to be_a(A2A::Server::TaskManager)
      expect(handler.push_notification_manager).to be_a(A2A::Server::PushNotificationManager)
    end
  end

  describe "#on_get_task" do
    let(:task_id) { "task-123" }
    let(:params) { { "id" => task_id } }
    let(:task) { A2A::Types::Task.new(id: task_id, context_id: "ctx-1", status: A2A::Types::TaskStatus.new(state: "completed")) }

    before do
      allow(handler.task_manager).to receive(:get_task).with(task_id, history_length: nil).and_return(task)
    end

    it "retrieves a task by ID" do
      result = handler.on_get_task(params)
      expect(result).to eq(task)
    end

    it "returns nil when task not found" do
      allow(handler.task_manager).to receive(:get_task).and_raise(A2A::Errors::TaskNotFound)
      result = handler.on_get_task(params)
      expect(result).to be_nil
    end

    it "raises error when task ID is missing" do
      expect { handler.on_get_task({}) }.to raise_error(A2A::Errors::InvalidParams, "Task ID is required")
    end

    it "passes history length parameter" do
      params_with_history = { "id" => task_id, "historyLength" => 10 }
      expect(handler.task_manager).to receive(:get_task).with(task_id, history_length: 10)
      handler.on_get_task(params_with_history)
    end
  end

  describe "#on_cancel_task" do
    let(:task_id) { "task-123" }
    let(:params) { { "id" => task_id } }
    let(:task) { A2A::Types::Task.new(id: task_id, context_id: "ctx-1", status: A2A::Types::TaskStatus.new(state: "canceled")) }

    it "raises error when task ID is missing" do
      expect { handler.on_cancel_task({}) }.to raise_error(A2A::Errors::InvalidParams, "Task ID is required")
    end

    it "cancels a task through agent executor" do
      allow(agent_executor).to receive(:cancel)
      allow(handler.task_manager).to receive(:get_task).with(task_id).and_return(task)

      result = handler.on_cancel_task(params)
      expect(result).to eq(task)
      expect(agent_executor).to have_received(:cancel)
    end

    it "returns nil when task not found" do
      allow(agent_executor).to receive(:cancel)
      allow(handler.task_manager).to receive(:get_task).and_raise(A2A::Errors::TaskNotFound)

      result = handler.on_cancel_task(params)
      expect(result).to be_nil
    end
  end

  describe "#on_message_send" do
    let(:message_data) do
      {
        message_id: "msg-1",
        context_id: "ctx-1",
        role: "user",
        parts: [{ kind: "text", text: "Hello" }]
      }
    end
    let(:params) { { "message" => message_data } }
    let(:task) { A2A::Types::Task.new(id: "task-1", context_id: "ctx-1", status: A2A::Types::TaskStatus.new(state: "completed")) }

    before do
      allow(agent_executor).to receive(:execute)
      allow(handler.task_manager).to receive(:get_task).and_return(task)
    end

    it "processes a message through agent executor" do
      # Mock the event processing to return a result quickly
      allow(handler).to receive(:setup_event_processing) do |_, _, _, &block|
        # Simulate completed task event
        event = double(type: "task", data: task)
        block&.call(event) if block
      end

      result = handler.on_message_send(params)
      expect(result).to eq(task)
      expect(agent_executor).to have_received(:execute)
    end
  end

  describe "push notification methods" do
    let(:task_id) { "task-123" }
    let(:config_data) { { "url" => "https://example.com/webhook" } }
    let(:config) { A2A::Types::TaskPushNotificationConfig.new(task_id: task_id, push_notification_config: config_data) }

    before do
      allow(handler.task_manager).to receive(:get_task).and_return(double)
      allow(handler.push_notification_manager).to receive(:set_push_notification_config).and_return(config)
      allow(handler.push_notification_manager).to receive(:get_push_notification_config).and_return(config)
      allow(handler.push_notification_manager).to receive(:list_push_notification_configs).and_return([config])
      allow(handler.push_notification_manager).to receive(:delete_push_notification_config).and_return(true)
    end

    describe "#on_set_task_push_notification_config" do
      let(:params) { { "taskId" => task_id, "config" => config_data } }

      it "sets push notification config" do
        result = handler.on_set_task_push_notification_config(params)
        expect(result).to eq(config)
      end

      it "raises error when task ID is missing" do
        expect { handler.on_set_task_push_notification_config({ "config" => config_data }) }
          .to raise_error(A2A::Errors::InvalidParams, "Task ID is required")
      end

      it "raises error when config is missing" do
        expect { handler.on_set_task_push_notification_config({ "taskId" => task_id }) }
          .to raise_error(A2A::Errors::InvalidParams, "Config is required")
      end
    end

    describe "#on_get_task_push_notification_config" do
      let(:params) { { "taskId" => task_id } }

      it "gets push notification config" do
        result = handler.on_get_task_push_notification_config(params)
        expect(result).to eq(config)
      end

      it "raises error when task ID is missing" do
        expect { handler.on_get_task_push_notification_config({}) }
          .to raise_error(A2A::Errors::InvalidParams, "Task ID is required")
      end

      it "raises error when config not found" do
        allow(handler.push_notification_manager).to receive(:get_push_notification_config).and_return(nil)
        expect { handler.on_get_task_push_notification_config(params) }
          .to raise_error(A2A::Errors::NotFound, "Push notification config not found")
      end
    end

    describe "#on_list_task_push_notification_config" do
      let(:params) { { "taskId" => task_id } }

      it "lists push notification configs" do
        result = handler.on_list_task_push_notification_config(params)
        expect(result).to eq([config])
      end

      it "raises error when task ID is missing" do
        expect { handler.on_list_task_push_notification_config({}) }
          .to raise_error(A2A::Errors::InvalidParams, "Task ID is required")
      end
    end

    describe "#on_delete_task_push_notification_config" do
      let(:params) { { "taskId" => task_id, "configId" => "config-1" } }

      it "deletes push notification config" do
        expect { handler.on_delete_task_push_notification_config(params) }.not_to raise_error
      end

      it "raises error when task ID is missing" do
        expect { handler.on_delete_task_push_notification_config({ "configId" => "config-1" }) }
          .to raise_error(A2A::Errors::InvalidParams, "Task ID and config ID are required")
      end

      it "raises error when config ID is missing" do
        expect { handler.on_delete_task_push_notification_config({ "taskId" => task_id }) }
          .to raise_error(A2A::Errors::InvalidParams, "Task ID and config ID are required")
      end

      it "raises error when config not found" do
        allow(handler.push_notification_manager).to receive(:delete_push_notification_config).and_return(false)
        expect { handler.on_delete_task_push_notification_config(params) }
          .to raise_error(A2A::Errors::NotFound, "Push notification config not found")
      end
    end
  end
end