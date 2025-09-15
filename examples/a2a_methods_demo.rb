#!/usr/bin/env ruby
# frozen_string_literal: true

# Demo script showing A2A protocol methods implementation
require_relative "../lib/a2a"

# Example agent that includes A2A methods
class DemoAgent
  include A2A::Server::Agent
  include A2A::Server::A2AMethods

  # Configure the agent
  a2a_config name: "Demo A2A Agent",
    description: "Demonstrates A2A protocol methods",
    version: "1.0.0",
    default_input_modes: ["text"],
    default_output_modes: ["text"]

  # Define a simple capability
  a2a_capability "echo" do
    method :echo
    description "Echo back the input message"
    input_schema type: "object",
      properties: { message: { type: "string" } },
      required: ["message"]
    output_schema type: "object",
      properties: { echo: { type: "string" } }
    tags %w[utility demo]
  end

  # Define a custom method
  a2a_method "echo" do |params, _context|
    message = params["message"]
    { echo: "You said: #{message}" }
  end

  protected

  def process_message_sync(message, task, _context)
    # Extract text from message parts
    text_parts = message.parts.select { |part| part.is_a?(A2A::Types::TextPart) }
    text_content = text_parts.map(&:text).join(" ")

    # Simple echo response
    response_message = A2A::Types::Message.new(
      message_id: SecureRandom.uuid,
      role: A2A::Types::ROLE_AGENT,
      parts: [
        A2A::Types::TextPart.new(text: "Echo: #{text_content}")
      ],
      context_id: message.context_id,
      task_id: task.id
    )

    {
      message: response_message.to_h,
      processed_at: Time.now.utc.iso8601
    }
  end

  def process_message_async(message, task, context)
    # For demo, just call sync version
    result = process_message_sync(message, task, context)

    # Update task status
    task_manager.update_task_status(
      task.id,
      A2A::Types::TaskStatus.new(
        state: A2A::Types::TASK_STATE_COMPLETED,
        result: result,
        updated_at: Time.now.utc.iso8601
      )
    )
  end

  def process_message_stream(_message, _task, _context)
    # Stream back a simple response
    3.times do |i|
      yield({
        chunk: i,
        text: "Streaming response #{i + 1}",
        timestamp: Time.now.utc.iso8601
      })
      sleep 0.1 # Small delay for demo
    end
  end

  def generate_agent_card(_context)
    A2A::Types::AgentCard.new(
      name: self.class._a2a_config[:name] || "Demo Agent",
      description: self.class._a2a_config[:description] || "A demo A2A agent",
      version: self.class._a2a_config[:version] || "1.0.0",
      url: "https://example.com/demo-agent",
      preferred_transport: A2A::Types::TRANSPORT_JSONRPC,
      skills: [
        A2A::Types::AgentSkill.new(
          id: "echo",
          name: "Echo Skill",
          description: "Echoes back user input"
        )
      ],
      capabilities: A2A::Types::AgentCapabilities.new(
        streaming: true,
        push_notifications: true,
        state_transition_history: true
      ),
      default_input_modes: ["text"],
      default_output_modes: ["text"],
      additional_interfaces: [
        A2A::Types::AgentInterface.new(
          transport: A2A::Types::TRANSPORT_JSONRPC,
          url: "https://example.com/demo-agent/rpc"
        )
      ],
      supports_authenticated_extended_card: true,
      protocol_version: "1.0"
    )
  end
end

# Demo the A2A methods
puts "=== A2A Protocol Methods Demo ==="
puts

agent = DemoAgent.new
context = A2A::Server::Context.new

# Demo 1: Get agent card
puts "1. Getting agent card..."
card_result = agent.handle_agent_get_card({}, context)
puts "Agent name: #{card_result[:agent_card]["name"]}"
puts "Agent description: #{card_result[:agent_card]["description"]}"
puts "Supports streaming: #{card_result[:agent_card]["capabilities"]["streaming"]}"
puts

# Demo 2: Send a message (blocking)
puts "2. Sending a message (blocking)..."
message_data = {
  "message_id" => SecureRandom.uuid,
  "role" => "user",
  "parts" => [
    { "kind" => "text", "text" => "Hello, demo agent!" }
  ],
  "context_id" => SecureRandom.uuid
}

send_result = agent.handle_message_send({
  "message" => message_data,
  "blocking" => true
}, context)

puts "Task ID: #{send_result[:task_id]}"
puts "Result: #{send_result[:result][:message]["parts"].first["text"]}"
puts

# Demo 3: Create and manage a task
puts "3. Creating and managing a task..."
task = agent.task_manager.create_task(
  type: "demo_task",
  params: { demo: true }
)

puts "Created task: #{task.id}"
puts "Initial status: #{task.status.state}"

# Get the task
get_result = agent.handle_tasks_get({ "id" => task.id }, context)
puts "Retrieved task status: #{get_result[:task]["status"]["state"]}"

# Cancel the task
cancel_result = agent.handle_tasks_cancel({ "id" => task.id }, context)
puts "Canceled task status: #{cancel_result[:status]["state"]}"
puts

# Demo 4: Push notification config
puts "4. Managing push notification config..."
config_task = agent.task_manager.create_task(
  type: "notification_demo",
  params: { demo: true }
)

# Set push notification config
set_result = agent.handle_push_notification_config_set({
  "taskId" => config_task.id,
  "config" => {
    "url" => "https://example.com/webhook",
    "token" => "demo-token"
  }
}, context)

puts "Set push notification config for task: #{set_result[:task_id]}"
puts "Webhook URL: #{set_result[:config]["url"]}"

# List configs
list_result = agent.handle_push_notification_config_list({
  "taskId" => config_task.id
}, context)

puts "Number of configs: #{list_result[:configs].length}"
puts

# Demo 5: Message streaming
puts "5. Streaming message response..."
stream_message_data = {
  "message_id" => SecureRandom.uuid,
  "role" => "user",
  "parts" => [
    { "kind" => "text", "text" => "Stream this message!" }
  ],
  "context_id" => SecureRandom.uuid
}

stream_result = agent.handle_message_stream({
  "message" => stream_message_data
}, context)

puts "Streaming responses:"
stream_result.each_with_index do |response, index|
  puts "  #{index + 1}. #{response[:response][:text]}"
end
puts

puts "=== Demo completed successfully! ==="
puts "All A2A protocol methods are working correctly."
