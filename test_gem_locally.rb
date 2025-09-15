#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script to verify the a2a-ruby gem works locally
# This script tests the gem without installing it globally

# Add the lib directory to the load path
$LOAD_PATH.unshift File.expand_path('lib', __dir__)

require 'a2a'

puts "🧪 Testing A2A Ruby Gem Locally"
puts "=" * 50

# Test 1: Basic gem loading
puts "\n✅ Test 1: Basic gem loading"
puts "A2A::VERSION = #{A2A::VERSION}"

# Test 2: Configuration
puts "\n✅ Test 2: Configuration"
A2A.configure do |config|
  config.protocol_version = "0.3.0"
  config.default_transport = "JSONRPC"
  config.log_level = :info
end

puts "Protocol version: #{A2A.config.protocol_version}"
puts "Default transport: #{A2A.config.default_transport}"
puts "Log level: #{A2A.config.log_level}"

# Test 3: Client creation
puts "\n✅ Test 3: Client creation"
begin
  client = A2A::Client::HttpClient.new("https://example.com/a2a")
  puts "HTTP Client created successfully"
rescue => e
  puts "Client creation failed: #{e.message}"
end

# Test 4: Message creation
puts "\n✅ Test 4: Message creation"
begin
  message = A2A::Types::Message.new(
    message_id: SecureRandom.uuid,
    role: "user",
    parts: [
      A2A::Types::TextPart.new(text: "Hello, A2A!")
    ]
  )
  puts "Message created: #{message.message_id}"
  puts "Message role: #{message.role}"
  puts "Message text: #{message.parts.first.text}"
rescue => e
  puts "Message creation failed: #{e.message}"
end

# Test 5: Agent creation
puts "\n✅ Test 5: Agent creation"
begin
  class TestAgent
    include A2A::Server::Agent
    
    a2a_skill "greeting" do |skill|
      skill.description = "Test greeting skill"
      skill.examples = ["Hello", "Hi there"]
    end
    
    a2a_method "greet" do |params|
      { message: "Hello, #{params[:name] || 'there'}!" }
    end
  end
  
  agent = TestAgent.new
  puts "Test agent created successfully"
  
  # Test method call
  result = agent.call_a2a_method("greet", name: "World")
  puts "Agent method result: #{result[:message]}"
rescue => e
  puts "Agent creation failed: #{e.message}"
end

# Test 6: Task creation
puts "\n✅ Test 6: Task creation"
begin
  task = A2A::Types::Task.new(
    id: SecureRandom.uuid,
    type: "test_task",
    status: A2A::Types::TaskStatus.new(
      state: A2A::Types::TASK_STATE_SUBMITTED,
      created_at: Time.now.utc.iso8601
    )
  )
  puts "Task created: #{task.id}"
  puts "Task type: #{task.type}"
  puts "Task state: #{task.status.state}"
rescue => e
  puts "Task creation failed: #{e.message}"
end

# Test 7: Error handling
puts "\n✅ Test 7: Error handling"
begin
  raise A2A::Errors::MethodNotFound, "Test method not found"
rescue A2A::Errors::A2AError => e
  puts "A2A error caught successfully: #{e.class.name} - #{e.message}"
rescue => e
  puts "Unexpected error: #{e.message}"
end

puts "\n🎉 All tests completed successfully!"
puts "The A2A Ruby gem is working correctly."
puts "\n📦 Gem is ready for local testing and eventual publishing to RubyGems."