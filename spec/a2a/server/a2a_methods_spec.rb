# frozen_string_literal: true

require 'spec_helper'

RSpec.describe A2A::Server::A2AMethods do
  let(:agent_class) do
    Class.new do
      include A2A::Server::Agent
      include A2A::Server::A2AMethods

      a2a_config name: "Test Agent",
                 description: "A test agent",
                 version: "1.0.0"

      protected

      def process_message_sync(message, task, context)
        {
          message: "Processed: #{message.parts.first.text}",
          task_id: task.id
        }
      end

      def process_message_async(message, task, context)
        # Simulate async processing
        Thread.new do
          sleep 0.1
          task_manager.update_task_status(
            task.id,
            A2A::Types::TaskStatus.new(
              state: A2A::Types::TASK_STATE_COMPLETED,
              result: { processed: true },
              updated_at: Time.now.utc.iso8601
            )
          )
        end
      end

      def process_message_stream(message, task, context)
        3.times do |i|
          yield({ chunk: i, text: "Stream #{i}" })
        end
      end

      def generate_agent_card(context)
        A2A::Types::AgentCard.new(
          name: "Test Agent",
          description: "A test agent",
          version: "1.0.0",
          url: "https://example.com/agent",
          preferred_transport: A2A::Types::TRANSPORT_JSONRPC,
          skills: [
            A2A::Types::AgentSkill.new(
              id: "test",
              name: "Test Skill",
              description: "A test skill"
            )
          ],
          capabilities: A2A::Types::AgentCapabilities.new(streaming: true),
          default_input_modes: ["text"],
          default_output_modes: ["text"]
        )
      end
    end
  end

  let(:agent) { agent_class.new }
  let(:context) { A2A::Server::Context.new }

  describe "#handle_message_send" do
    let(:message_data) do
      {
        'message_id' => 'msg-123',
        'role' => 'user',
        'parts' => [
          { 'kind' => 'text', 'text' => 'Hello, agent!' }
        ],
        'context_id' => 'ctx-123'
      }
    end

    it "processes message synchronously when blocking is true" do
      params = {
        'message' => message_data,
        'blocking' => true
      }

      result = agent.handle_message_send(params, context)

      expect(result).to include(:task_id, :context_id, :result)
      expect(result[:context_id]).to eq('ctx-123')
      expect(result[:result]).to include(:message)
    end

    it "processes message asynchronously when blocking is false" do
      params = {
        'message' => message_data,
        'blocking' => false
      }

      result = agent.handle_message_send(params, context)

      expect(result).to include(:task_id, :context_id, :status)
      expect(result[:context_id]).to eq('ctx-123')
      expect(result[:status]).to include('state' => A2A::Types::TASK_STATE_SUBMITTED)
    end

    it "raises error when message parameter is missing" do
      params = { 'blocking' => true }

      expect {
        agent.handle_message_send(params, context)
      }.to raise_error(A2A::Errors::InvalidParams, /Missing required parameters: message/)
    end
  end

  describe "#handle_message_stream" do
    let(:message_data) do
      {
        'message_id' => 'msg-123',
        'role' => 'user',
        'parts' => [
          { 'kind' => 'text', 'text' => 'Stream this!' }
        ],
        'context_id' => 'ctx-123'
      }
    end

    it "returns an enumerator for streaming responses" do
      params = { 'message' => message_data }

      result = agent.handle_message_stream(params, context)

      expect(result).to be_a(Enumerator)
      
      responses = result.to_a
      expect(responses.length).to eq(3)
      expect(responses.first).to include(:task_id, :context_id, :response)
    end
  end

  describe "#handle_tasks_get" do
    it "retrieves a task by ID" do
      # Create a task first
      task = agent.task_manager.create_task(
        type: 'test',
        params: { test: true }
      )

      params = { 'id' => task.id }
      result = agent.handle_tasks_get(params, context)

      expect(result).to include(:task)
      expect(result[:task]).to include('id' => task.id)
    end

    it "raises error when task is not found" do
      params = { 'id' => 'nonexistent' }

      expect {
        agent.handle_tasks_get(params, context)
      }.to raise_error(A2A::Errors::TaskNotFound)
    end

    it "limits history when historyLength is specified" do
      # Create a task and add multiple messages
      task = agent.task_manager.create_task(
        type: 'test',
        params: { test: true }
      )

      # Add some messages to history
      5.times do |i|
        message = A2A::Types::Message.new(
          message_id: "msg-#{i}",
          role: A2A::Types::ROLE_USER,
          parts: [A2A::Types::TextPart.new(text: "Message #{i}")]
        )
        agent.task_manager.add_message(task.id, message)
      end

      params = { 'id' => task.id, 'historyLength' => 2 }
      result = agent.handle_tasks_get(params, context)

      expect(result[:task]['history'].length).to eq(2)
    end
  end

  describe "#handle_tasks_cancel" do
    it "cancels a task successfully" do
      task = agent.task_manager.create_task(
        type: 'test',
        params: { test: true }
      )

      params = { 'id' => task.id, 'reason' => 'User requested' }
      result = agent.handle_tasks_cancel(params, context)

      expect(result).to include(:task_id, :status)
      expect(result[:task_id]).to eq(task.id)
      expect(result[:status]).to include('state' => A2A::Types::TASK_STATE_CANCELED)
    end

    it "raises error when task cannot be canceled" do
      task = agent.task_manager.create_task(
        type: 'test',
        params: { test: true }
      )

      # Complete the task first
      agent.task_manager.update_task_status(
        task.id,
        A2A::Types::TaskStatus.new(
          state: A2A::Types::TASK_STATE_COMPLETED,
          updated_at: Time.now.utc.iso8601
        )
      )

      params = { 'id' => task.id }

      expect {
        agent.handle_tasks_cancel(params, context)
      }.to raise_error(A2A::Errors::TaskNotCancelable)
    end
  end

  describe "#handle_push_notification_config_set" do
    it "sets a push notification config for a task" do
      task = agent.task_manager.create_task(
        type: 'test',
        params: { test: true }
      )

      config_data = {
        'url' => 'https://example.com/webhook',
        'token' => 'secret-token'
      }

      params = {
        'taskId' => task.id,
        'config' => config_data
      }

      result = agent.handle_push_notification_config_set(params, context)

      expect(result).to include(:task_id, :config)
      expect(result[:task_id]).to eq(task.id)
      expect(result[:config]).to include('url' => 'https://example.com/webhook')
    end
  end

  describe "#handle_push_notification_config_get" do
    it "retrieves a push notification config" do
      task = agent.task_manager.create_task(
        type: 'test',
        params: { test: true }
      )

      # Set a config first
      config_data = {
        'url' => 'https://example.com/webhook',
        'token' => 'secret-token'
      }
      
      config = agent.push_notification_manager.set_push_notification_config(task.id, config_data)

      params = {
        'taskId' => task.id,
        'configId' => config.push_notification_config.id
      }

      result = agent.handle_push_notification_config_get(params, context)

      expect(result).to include(:task_id, :config)
      expect(result[:config]).to include('url' => 'https://example.com/webhook')
    end

    it "raises error when config is not found" do
      task = agent.task_manager.create_task(
        type: 'test',
        params: { test: true }
      )

      params = {
        'taskId' => task.id,
        'configId' => 'nonexistent'
      }

      expect {
        agent.handle_push_notification_config_get(params, context)
      }.to raise_error(A2A::Errors::NotFound)
    end
  end

  describe "#handle_agent_get_card" do
    it "returns the agent card" do
      result = agent.handle_agent_get_card({}, context)

      expect(result).to include(:agent_card)
      expect(result[:agent_card]).to include('name' => 'Test Agent')
    end
  end

  describe "#handle_agent_get_authenticated_extended_card" do
    it "returns extended agent card when authenticated" do
      context.set_authentication('bearer', 'token-123')
      context.set_user('user-123')

      result = agent.handle_agent_get_authenticated_extended_card({}, context)

      expect(result).to include(:agent_card)
      expect(result[:agent_card]).to include('name' => 'Test Agent')
    end

    it "raises error when not authenticated" do
      expect {
        agent.handle_agent_get_authenticated_extended_card({}, context)
      }.to raise_error(A2A::Errors::AuthenticationRequired)
    end
  end
end