# Framework Integration Guide

This guide covers integrating the A2A Ruby SDK with different Ruby frameworks.

## Rails Integration

### Installation

```ruby
# Gemfile
gem 'a2a-ruby'
```

### Setup

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount A2A::Engine => "/a2a"
end

# config/application.rb or config/environments/production.rb
A2A.configure do |config|
  config.protocol_version = "0.3.0"
  config.default_transport = "JSONRPC"
  config.streaming_enabled = true
end
```

### Creating Agents

```ruby
# app/controllers/agent_controller.rb
class AgentController < ApplicationController
  include A2A::Server::Agent
  
  # Define agent capabilities
  a2a_skill "greeting" do |skill|
    skill.description = "Greet users in different languages"
    skill.examples = ["Hello", "Say hi in Spanish"]
  end
  
  # Define A2A methods
  a2a_method "greet" do |params|
    language = params[:language] || "en"
    name = params[:name] || "there"
    
    greeting = case language
    when "es" then "¡Hola"
    when "fr" then "Bonjour"
    else "Hello"
    end
    
    { message: "#{greeting}, #{name}!" }
  end
  
  # Streaming responses
  a2a_method "chat", streaming: true do |params|
    Enumerator.new do |yielder|
      # Process and stream response
      response = process_chat(params[:message])
      yielder << A2A::Types::Message.new(
        message_id: SecureRandom.uuid,
        role: "agent",
        parts: [A2A::Types::TextPart.new(text: response)]
      )
    end
  end
  
  private
  
  def process_chat(message)
    # Your chat processing logic
    "You said: #{message}"
  end
end
```

## Sinatra Integration

### Basic Setup

```ruby
# app.rb
require 'sinatra'
require 'a2a'

# Configure A2A
A2A.configure do |config|
  config.protocol_version = "0.3.0"
  config.default_transport = "JSONRPC"
end

class MyAgent
  include A2A::Server::Agent
  
  a2a_method "echo" do |params|
    { message: "Echo: #{params[:text]}" }
  end
end

# Mount A2A endpoints
post '/a2a/rpc' do
  content_type :json
  agent = MyAgent.new
  agent.handle_request(request.body.read)
end

get '/a2a/agent-card' do
  content_type :json
  MyAgent.new.generate_agent_card.to_json
end
```

## Plain Ruby Integration

### Standalone Agent

```ruby
#!/usr/bin/env ruby
require 'a2a'

class StandaloneAgent
  include A2A::Server::Agent
  
  a2a_method "process" do |params|
    # Your processing logic
    { result: "Processed: #{params[:input]}" }
  end
end

# Start HTTP server
require 'webrick'

server = WEBrick::HTTPServer.new(Port: 8080)
agent = StandaloneAgent.new

server.mount_proc '/a2a/rpc' do |req, res|
  if req.request_method == 'POST'
    res.content_type = 'application/json'
    res.body = agent.handle_request(req.body)
  end
end

trap('INT') { server.shutdown }
server.start
```

### Client Usage

```ruby
require 'a2a'

# Create client
client = A2A::Client::HttpClient.new("http://localhost:8080/a2a")

# Send message
message = A2A::Types::Message.new(
  message_id: SecureRandom.uuid,
  role: "user",
  parts: [A2A::Types::TextPart.new(text: "Hello!")]
)

response = client.send_message(message)
puts response.inspect
```

## Testing

### RSpec Integration

```ruby
# spec/spec_helper.rb
require 'a2a'
require 'a2a/testing'

RSpec.configure do |config|
  config.include A2A::Testing::Helpers
end

# spec/agents/my_agent_spec.rb
RSpec.describe MyAgent do
  include A2A::Testing::Helpers
  
  it "responds to greet method" do
    agent = MyAgent.new
    response = agent.call_a2a_method("greet", name: "World")
    
    expect(response[:message]).to eq("Hello, World!")
  end
  
  it "handles streaming responses" do
    agent = MyAgent.new
    responses = []
    
    agent.call_a2a_method("chat", message: "Hi") do |response|
      responses << response
    end
    
    expect(responses).not_to be_empty
  end
end
```

## Common Patterns

### Error Handling

```ruby
a2a_method "risky_operation" do |params|
  begin
    # Your operation
    { success: true }
  rescue StandardError => e
    raise A2A::Errors::InternalError, "Operation failed: #{e.message}"
  end
end
```

### Authentication

```ruby
class SecureAgent
  include A2A::Server::Agent
  
  before_a2a_method do |context|
    unless context.authenticated?
      raise A2A::Errors::AuthenticationRequired, "Authentication required"
    end
  end
  
  a2a_method "secure_operation" do |params|
    # Only authenticated requests reach here
    { result: "Success" }
  end
end
```

### Background Processing

```ruby
# With Sidekiq (Rails)
a2a_method "long_task", async: true do |params|
  LongTaskWorker.perform_async(params[:task_id], params[:data])
  { task_id: params[:task_id], status: "queued" }
end

class LongTaskWorker
  include Sidekiq::Worker
  
  def perform(task_id, data)
    # Process task
    result = process_data(data)
    
    # Update task status
    A2A::TaskManager.update_task(task_id, 
      status: "completed", 
      result: result
    )
  end
end
```