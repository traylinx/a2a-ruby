# Getting Started with A2A Ruby SDK

Welcome to the A2A Ruby SDK! This guide will help you get up and running with Google's Agent2Agent (A2A) Protocol in your Ruby applications.

## Table of Contents

- [Installation](#installation)
- [Basic Concepts](#basic-concepts)
- [Your First A2A Client](#your-first-a2a-client)
- [Your First A2A Server](#your-first-a2a-server)
- [Rails Integration](#rails-integration)
- [Authentication](#authentication)
- [Task Management](#task-management)
- [Troubleshooting](#troubleshooting)
- [Next Steps](#next-steps)

## Installation

### Requirements

- Ruby 2.7 or higher
- Bundler

### Install the Gem

Add to your Gemfile:

```ruby
gem 'a2a-ruby'
```

Then run:

```bash
bundle install
```

Or install directly:

```bash
gem install a2a-ruby
```

### Verify Installation

```ruby
require 'a2a'
puts A2A::VERSION
```

## Basic Concepts

### Agent2Agent Protocol

The A2A protocol enables agents to communicate with each other using standardized message formats and transport protocols. Key concepts include:

- **Messages**: Structured communication between agents
- **Tasks**: Long-running operations with lifecycle management
- **Agent Cards**: Self-describing agent capabilities
- **Transports**: Communication protocols (JSON-RPC, gRPC, HTTP+JSON)

### Core Components

- **Client**: Consumes services from other agents
- **Server**: Exposes your application as an A2A agent
- **Types**: Protocol-compliant data structures
- **Transport**: Communication layer (HTTP, gRPC, SSE)

## Your First A2A Client

Let's create a simple client to communicate with an A2A agent:

```ruby
require 'a2a'

# Create a client pointing to an A2A agent
client = A2A::Client::HttpClient.new("https://example-agent.com/a2a")

# Create a message
message = A2A::Types::Message.new(
  message_id: SecureRandom.uuid,
  role: "user",
  parts: [
    A2A::Types::TextPart.new(text: "What's the weather like today?")
  ]
)

# Send the message and handle responses
begin
  client.send_message(message) do |response|
    case response
    when A2A::Types::Message
      puts "Agent: #{response.parts.first.text}"
    when A2A::Types::TaskStatusUpdateEvent
      puts "Task Status: #{response.status.state}"
    when A2A::Types::Task
      puts "Task Created: #{response.id}"
    end
  end
rescue A2A::Errors::ClientError => e
  puts "Error: #{e.message}"
end
```

### Client Configuration

```ruby
# Configure client behavior
config = A2A::Client::Config.new
config.streaming = true
config.timeout = 60
config.supported_transports = ['JSONRPC', 'HTTP+JSON']

client = A2A::Client::HttpClient.new(
  "https://example-agent.com/a2a",
  config: config
)
```

### Working with Tasks

```ruby
# Get task status
task = client.get_task("task-123")
puts "Task state: #{task.status.state}"

# Cancel a task
client.cancel_task("task-123")

# Resubscribe to task updates
client.resubscribe("task-123") do |event|
  puts "Task update: #{event.status.state}"
end
```

## Your First A2A Server

Create an A2A server to expose your application's capabilities:

### Plain Ruby Server

```ruby
require 'a2a'
require 'sinatra'

class WeatherAgent
  include A2A::Server::Agent
  
  # Define agent skills
  a2a_skill "weather_lookup" do |skill|
    skill.description = "Get current weather information"
    skill.tags = ["weather", "information"]
    skill.examples = ["What's the weather in San Francisco?"]
    skill.input_modes = ["text"]
    skill.output_modes = ["text"]
  end
  
  # Define A2A methods
  a2a_method "get_weather" do |params|
    location = params[:location] || "Unknown"
    
    # Simulate weather lookup
    {
      location: location,
      temperature: "72°F",
      condition: "Sunny",
      timestamp: Time.current.iso8601
    }
  end
  
  # Streaming method example
  a2a_method "weather_forecast", streaming: true do |params|
    Enumerator.new do |yielder|
      # Yield status updates
      yielder << A2A::Types::TaskStatusUpdateEvent.new(
        task_id: params[:task_id],
        context_id: params[:context_id],
        status: A2A::Types::TaskStatus.new(state: "working")
      )
      
      # Generate forecast data
      5.times do |day|
        forecast = {
          day: day + 1,
          temperature: "#{70 + rand(10)}°F",
          condition: ["Sunny", "Cloudy", "Rainy"].sample
        }
        
        yielder << A2A::Types::Message.new(
          message_id: SecureRandom.uuid,
          role: "agent",
          parts: [A2A::Types::TextPart.new(text: forecast.to_json)]
        )
      end
      
      # Final status
      yielder << A2A::Types::TaskStatusUpdateEvent.new(
        task_id: params[:task_id],
        context_id: params[:context_id],
        status: A2A::Types::TaskStatus.new(state: "completed")
      )
    end
  end
end

# Sinatra integration
post '/a2a/rpc' do
  content_type :json
  
  agent = WeatherAgent.new
  request_body = request.body.read
  
  begin
    json_rpc_request = A2A::Protocol::JsonRpc.parse_request(request_body)
    response = agent.handle_a2a_request(json_rpc_request)
    response.to_json
  rescue A2A::Errors::A2AError => e
    status 400
    e.to_json_rpc_error.to_json
  end
end

get '/a2a/agent-card' do
  content_type :json
  
  agent = WeatherAgent.new
  card = agent.generate_agent_card(
    name: "Weather Agent",
    description: "Provides weather information and forecasts",
    version: "1.0.0",
    url: "#{request.base_url}/a2a"
  )
  
  card.to_h.to_json
end
```

## Rails Integration

The A2A Ruby SDK provides seamless Rails integration through an engine.

### Setup

Generate the A2A configuration:

```bash
rails generate a2a:install
```

This creates:
- `config/initializers/a2a.rb` - Configuration file
- Routes for A2A endpoints
- Database migrations (if using ActiveRecord storage)

### Create an Agent Controller

```bash
rails generate a2a:agent weather
```

This generates:
- `app/controllers/weather_agent_controller.rb`
- Spec file
- README with usage instructions

### Example Agent Controller

```ruby
class WeatherAgentController < ApplicationController
  include A2A::Rails::ControllerHelpers
  
  # Define agent metadata
  a2a_config(
    name: "Weather Service Agent",
    description: "Provides weather information and forecasts",
    version: "1.0.0"
  )
  
  # Define skills
  a2a_skill "weather_lookup" do |skill|
    skill.description = "Get current weather for any location"
    skill.tags = ["weather", "current", "lookup"]
    skill.examples = [
      "What's the weather in New York?",
      "Current conditions in Tokyo"
    ]
  end
  
  # A2A method implementations
  a2a_method "get_current_weather" do |params|
    location = params[:location]
    
    # Your weather service logic here
    weather_data = WeatherService.current(location)
    
    {
      location: location,
      temperature: weather_data.temperature,
      condition: weather_data.condition,
      humidity: weather_data.humidity,
      timestamp: Time.current.iso8601
    }
  end
  
  a2a_method "get_forecast", streaming: true do |params|
    location = params[:location]
    days = params[:days] || 5
    
    Enumerator.new do |yielder|
      # Initial status
      yielder << task_status_update("working", "Fetching forecast data...")
      
      # Get forecast data
      forecast = WeatherService.forecast(location, days)
      
      forecast.each_with_index do |day_forecast, index|
        # Yield each day's forecast
        message = A2A::Types::Message.new(
          message_id: SecureRandom.uuid,
          role: "agent",
          parts: [
            A2A::Types::TextPart.new(
              text: "Day #{index + 1}: #{day_forecast.condition}, #{day_forecast.temperature}"
            )
          ]
        )
        yielder << message
        
        # Progress update
        progress = ((index + 1).to_f / days * 100).round
        yielder << task_status_update("working", "Progress: #{progress}%", progress)
      end
      
      # Completion
      yielder << task_status_update("completed", "Forecast complete")
    end
  end
  
  private
  
  def task_status_update(state, message = nil, progress = nil)
    A2A::Types::TaskStatusUpdateEvent.new(
      task_id: params[:task_id],
      context_id: params[:context_id],
      status: A2A::Types::TaskStatus.new(
        state: state,
        message: message,
        progress: progress
      )
    )
  end
end
```

### Routes

The Rails engine automatically provides these routes:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount A2A::Engine => "/a2a"
  
  # This provides:
  # POST /a2a/rpc          - JSON-RPC endpoint
  # GET  /a2a/agent-card   - Agent card discovery
  # GET  /a2a/capabilities - Capabilities listing
end
```

## Authentication

### Client Authentication

```ruby
# OAuth 2.0
auth = A2A::Client::Auth::OAuth2.new(
  client_id: "your-client-id",
  client_secret: "your-client-secret",
  token_url: "https://auth.example.com/token"
)

client = A2A::Client::HttpClient.new(
  "https://agent.example.com/a2a",
  auth: auth
)

# JWT Bearer Token
auth = A2A::Client::Auth::JWT.new(token: "your-jwt-token")

# API Key
auth = A2A::Client::Auth::ApiKey.new(
  key: "your-api-key",
  header: "X-API-Key"  # or use query parameter
)
```

### Server Authentication

```ruby
class SecureAgentController < ApplicationController
  include A2A::Rails::ControllerHelpers
  
  # Configure authentication
  before_action :authenticate_a2a_request
  
  private
  
  def authenticate_a2a_request
    # JWT validation example
    token = request.headers['Authorization']&.sub(/^Bearer /, '')
    
    begin
      payload = JWT.decode(token, Rails.application.secret_key_base, true, algorithm: 'HS256')
      @current_user = User.find(payload[0]['user_id'])
    rescue JWT::DecodeError
      render json: { error: 'Invalid token' }, status: :unauthorized
    end
  end
end
```

## Task Management

### Creating and Managing Tasks

```ruby
# In your agent method
a2a_method "long_running_task" do |params|
  # Create a task
  task = create_task(
    type: "data_processing",
    params: params,
    metadata: { user_id: current_user.id }
  )
  
  # Start background processing
  ProcessDataJob.perform_later(task.id, params)
  
  # Return task immediately
  task
end

# Background job
class ProcessDataJob < ApplicationJob
  def perform(task_id, params)
    task_manager = A2A::Server::TaskManager.new
    
    begin
      # Update status
      task_manager.update_task_status(task_id, 
        A2A::Types::TaskStatus.new(state: "working")
      )
      
      # Do work...
      result = process_data(params)
      
      # Complete task
      task_manager.update_task_status(task_id,
        A2A::Types::TaskStatus.new(
          state: "completed",
          result: result
        )
      )
    rescue => e
      # Handle errors
      task_manager.update_task_status(task_id,
        A2A::Types::TaskStatus.new(
          state: "failed",
          error: { message: e.message, type: e.class.name }
        )
      )
    end
  end
end
```

### Push Notifications

```ruby
# Set up push notifications for a task
push_config = A2A::Types::PushNotificationConfig.new(
  url: "https://your-app.com/webhooks/a2a",
  authentication: {
    type: "bearer",
    token: "your-webhook-token"
  }
)

client.set_task_callback(task_id, push_config)

# Webhook handler
post '/webhooks/a2a' do
  # Verify authentication
  token = request.headers['Authorization']&.sub(/^Bearer /, '')
  halt 401 unless token == ENV['WEBHOOK_TOKEN']
  
  # Parse event
  event_data = JSON.parse(request.body.read)
  
  case event_data['type']
  when 'TaskStatusUpdateEvent'
    handle_task_status_update(event_data)
  when 'TaskArtifactUpdateEvent'
    handle_task_artifact_update(event_data)
  end
  
  status 200
end
```

## Troubleshooting

### Common Issues

#### Connection Errors

```ruby
begin
  client.send_message(message)
rescue A2A::Errors::HTTPError => e
  puts "HTTP Error: #{e.message}"
  # Check network connectivity and endpoint URL
rescue A2A::Errors::TimeoutError => e
  puts "Timeout: #{e.message}"
  # Increase timeout or check server performance
end
```

#### Authentication Failures

```ruby
begin
  client.send_message(message)
rescue A2A::Errors::AuthenticationError => e
  puts "Auth Error: #{e.message}"
  # Check credentials and token expiration
end
```

#### Protocol Errors

```ruby
begin
  response = client.send_message(message)
rescue A2A::Errors::InvalidRequest => e
  puts "Invalid Request: #{e.message}"
  # Check message format and required fields
rescue A2A::Errors::MethodNotFound => e
  puts "Method Not Found: #{e.message}"
  # Check agent card for available methods
end
```

### Debugging

Enable debug logging:

```ruby
A2A.configure do |config|
  config.log_level = :debug
end
```

Use the development console:

```bash
bin/console
```

```ruby
# Test agent card retrieval
client = A2A::Client::HttpClient.new("https://agent.example.com/a2a")
card = client.get_card
puts card.to_h.to_json
```

### Performance Issues

Monitor performance with built-in metrics:

```ruby
A2A.configure do |config|
  config.enable_metrics = true
  config.metrics_backend = :prometheus  # or :statsd
end
```

### FAQ

**Q: How do I handle file uploads in messages?**

A: Use `FilePart` with base64 encoding or URI references:

```ruby
# Base64 file
file_part = A2A::Types::FilePart.new(
  file: A2A::Types::FileWithBytes.new(
    name: "document.pdf",
    mime_type: "application/pdf",
    bytes: Base64.encode64(file_content)
  )
)

# URI reference
file_part = A2A::Types::FilePart.new(
  file: A2A::Types::FileWithUri.new(
    name: "document.pdf",
    mime_type: "application/pdf",
    uri: "https://storage.example.com/files/document.pdf"
  )
)
```

**Q: How do I implement custom authentication?**

A: Create a custom auth strategy:

```ruby
class CustomAuth < A2A::Client::Auth::Base
  def initialize(api_key)
    @api_key = api_key
  end
  
  def apply_auth(request)
    request.headers['X-Custom-Auth'] = @api_key
  end
end

client = A2A::Client::HttpClient.new(url, auth: CustomAuth.new("key"))
```

**Q: Can I use multiple transports?**

A: Yes, configure transport preferences:

```ruby
config = A2A::Client::Config.new
config.supported_transports = ['JSONRPC', 'GRPC', 'HTTP+JSON']
config.use_client_preference = true

client = A2A::Client::HttpClient.new(url, config: config)
```

## Next Steps

Now that you have the basics, explore these advanced topics:

- [Client Documentation](client.md) - Advanced client configuration and usage
- [Server Documentation](server.md) - Building production-ready A2A servers  
- [Rails Integration](rails.md) - Deep dive into Rails-specific features
- [Authentication Guide](authentication.md) - Comprehensive security setup
- [Deployment Guide](deployment.md) - Production deployment best practices
- [API Reference](https://rubydoc.info/gems/a2a-ruby) - Complete API documentation

### Example Applications

Check out complete example applications:

- [Weather Agent](https://github.com/a2aproject/a2a-ruby-examples/tree/main/weather-agent)
- [File Processing Service](https://github.com/a2aproject/a2a-ruby-examples/tree/main/file-processor)
- [Multi-Agent Chat](https://github.com/a2aproject/a2a-ruby-examples/tree/main/multi-agent-chat)

### Community

- [GitHub Discussions](https://github.com/a2aproject/a2a-ruby/discussions)
- [Issue Tracker](https://github.com/a2aproject/a2a-ruby/issues)
- [Contributing Guide](../CONTRIBUTING.md)