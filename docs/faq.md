# Frequently Asked Questions

## General Questions

### What is the A2A Protocol?

The Agent2Agent (A2A) Protocol is Google's specification for enabling seamless communication between AI agents. It provides standardized message formats, transport protocols, and lifecycle management for agent interactions.

### How does A2A Ruby SDK compare to the Python SDK?

The A2A Ruby SDK follows the same architecture and API patterns as the official Python SDK, ensuring compatibility and familiar developer experience. Key similarities:

- Same protocol compliance and message formats
- Identical transport support (JSON-RPC, gRPC, HTTP+JSON)
- Compatible agent card schemas
- Similar client/server patterns

### What Ruby versions are supported?

- Ruby 2.7 or higher
- Rails 6.0+ (for Rails integration)
- JRuby and TruffleRuby compatibility

## Installation and Setup

### How do I install the gem?

```bash
# Add to Gemfile
gem 'a2a-ruby'

# Or install directly
gem install a2a-ruby
```

### Do I need Rails to use A2A Ruby SDK?

No! The SDK works with any Ruby application:

- Plain Ruby scripts
- Sinatra applications  
- Rack applications
- Rails applications (with enhanced integration)

### How do I set up A2A in a Rails app?

```bash
# Generate configuration
rails generate a2a:install

# Create an agent
rails generate a2a:agent my_agent

# Run migrations (if using database storage)
rails db:migrate
```

## Client Usage

### How do I connect to an A2A agent?

```ruby
require 'a2a'

client = A2A::Client::HttpClient.new("https://agent.example.com/a2a")

# Send a message
message = A2A::Types::Message.new(
  message_id: SecureRandom.uuid,
  role: "user",
  parts: [A2A::Types::TextPart.new(text: "Hello!")]
)

client.send_message(message) do |response|
  puts response
end
```

### How do I handle authentication?

```ruby
# OAuth 2.0
auth = A2A::Client::Auth::OAuth2.new(
  client_id: "your-id",
  client_secret: "your-secret", 
  token_url: "https://auth.example.com/token"
)

# JWT
auth = A2A::Client::Auth::JWT.new(token: "your-jwt")

# API Key
auth = A2A::Client::Auth::ApiKey.new(
  key: "your-key",
  header: "X-API-Key"
)

client = A2A::Client::HttpClient.new(url, auth: auth)
```

### What's the difference between streaming and blocking calls?

```ruby
# Blocking - waits for complete response
response = client.send_message(message, streaming: false)

# Streaming - processes responses as they arrive
client.send_message(message, streaming: true) do |chunk|
  case chunk
  when A2A::Types::Message
    puts "Message: #{chunk.parts.first.text}"
  when A2A::Types::TaskStatusUpdateEvent
    puts "Status: #{chunk.status.state}"
  end
end
```

### How do I handle file uploads?

```ruby
# Base64 encoded file
file_part = A2A::Types::FilePart.new(
  file: A2A::Types::FileWithBytes.new(
    name: "document.pdf",
    mime_type: "application/pdf", 
    bytes: Base64.encode64(File.read("document.pdf"))
  )
)

# File by URI reference
file_part = A2A::Types::FilePart.new(
  file: A2A::Types::FileWithUri.new(
    name: "document.pdf",
    mime_type: "application/pdf",
    uri: "https://storage.example.com/document.pdf"
  )
)

message = A2A::Types::Message.new(
  message_id: SecureRandom.uuid,
  role: "user", 
  parts: [file_part]
)
```

## Server Development

### How do I create an A2A server?

```ruby
class MyAgent
  include A2A::Server::Agent
  
  # Define capabilities
  a2a_skill "greeting" do |skill|
    skill.description = "Greet users"
    skill.tags = ["greeting", "conversation"]
  end
  
  # Define methods
  a2a_method "greet" do |params|
    { message: "Hello, #{params[:name]}!" }
  end
end
```

### How do I handle streaming responses?

```ruby
a2a_method "stream_data", streaming: true do |params|
  Enumerator.new do |yielder|
    # Yield status updates
    yielder << A2A::Types::TaskStatusUpdateEvent.new(
      task_id: params[:task_id],
      context_id: params[:context_id], 
      status: A2A::Types::TaskStatus.new(state: "working")
    )
    
    # Yield data chunks
    data.each_slice(100) do |chunk|
      message = A2A::Types::Message.new(
        message_id: SecureRandom.uuid,
        role: "agent",
        parts: [A2A::Types::TextPart.new(text: chunk.to_json)]
      )
      yielder << message
    end
    
    # Final status
    yielder << A2A::Types::TaskStatusUpdateEvent.new(
      task_id: params[:task_id],
      context_id: params[:context_id],
      status: A2A::Types::TaskStatus.new(state: "completed")
    )
  end
end
```

### How do I implement authentication on the server?

```ruby
class SecureAgentController < ApplicationController
  include A2A::Rails::ControllerHelpers
  
  before_action :authenticate_a2a_request
  
  private
  
  def authenticate_a2a_request
    token = request.headers['Authorization']&.sub(/^Bearer /, '')
    
    begin
      payload = JWT.decode(token, secret_key, true, algorithm: 'HS256')
      @current_user = User.find(payload[0]['user_id'])
    rescue JWT::DecodeError
      render json: { error: 'Unauthorized' }, status: :unauthorized
    end
  end
end
```

### How do I generate agent cards?

Agent cards are automatically generated from your agent definition:

```ruby
class WeatherAgent
  include A2A::Server::Agent
  
  a2a_config(
    name: "Weather Service",
    description: "Provides weather information",
    version: "1.0.0"
  )
  
  a2a_skill "weather_lookup" do |skill|
    skill.description = "Get current weather"
    skill.tags = ["weather", "current"]
    skill.input_modes = ["text"]
    skill.output_modes = ["text", "structured"]
  end
end

# Card available at GET /a2a/agent-card
```

## Task Management

### How do I create and manage tasks?

```ruby
# Create a task
task = create_task(
  type: "data_processing",
  params: { file_id: "123" },
  metadata: { user_id: current_user.id }
)

# Update task status
update_task_status(task.id, 
  A2A::Types::TaskStatus.new(state: "working", progress: 50)
)

# Complete task
update_task_status(task.id,
  A2A::Types::TaskStatus.new(
    state: "completed", 
    result: { processed_records: 1000 }
  )
)
```

### What are the valid task states?

- `submitted` - Task created, waiting to start
- `working` - Task in progress
- `input-required` - Task needs user input
- `completed` - Task finished successfully
- `canceled` - Task was canceled
- `failed` - Task failed with error
- `rejected` - Task rejected (invalid params, etc.)
- `auth-required` - Task needs authentication
- `unknown` - Unknown state

### How do I set up push notifications?

```ruby
# Client side - set up webhook
push_config = A2A::Types::PushNotificationConfig.new(
  url: "https://your-app.com/webhooks/a2a",
  authentication: {
    type: "bearer",
    token: "webhook-secret"
  }
)

client.set_task_callback(task_id, push_config)

# Server side - handle webhooks
post '/webhooks/a2a' do
  # Verify authentication
  token = request.headers['Authorization']&.sub(/^Bearer /, '')
  halt 401 unless token == ENV['WEBHOOK_SECRET']
  
  # Process event
  event = JSON.parse(request.body.read)
  handle_task_event(event)
  
  status 200
end
```

## Transport and Protocols

### What transport protocols are supported?

- **JSON-RPC 2.0** over HTTP(S) - Primary transport
- **gRPC** - High-performance binary protocol  
- **HTTP+JSON** - Simple REST-like interface
- **Server-Sent Events** - For streaming responses

### How do I choose a transport?

```ruby
# Client preference
config = A2A::Client::Config.new
config.supported_transports = ['JSONRPC', 'GRPC']
config.use_client_preference = true

client = A2A::Client::HttpClient.new(url, config: config)

# The client will negotiate with the server based on agent card
```

### Can I use custom transports?

Yes, implement the transport interface:

```ruby
class CustomTransport < A2A::Transport::Base
  def send_request(request)
    # Your transport logic
  end
  
  def supports_streaming?
    true
  end
end

# Register transport
A2A.register_transport('CUSTOM', CustomTransport)
```

## Configuration

### How do I configure the SDK?

```ruby
A2A.configure do |config|
  config.protocol_version = "0.3.0"
  config.default_transport = "JSONRPC"
  config.streaming_enabled = true
  config.push_notifications_enabled = true
  config.default_timeout = 30
  config.log_level = :info
  config.storage_backend = :database  # :memory, :redis, :database
end
```

### What storage backends are available?

- **Memory** - In-memory storage (development/testing)
- **Database** - ActiveRecord/Sequel (production)
- **Redis** - Redis storage (distributed systems)

```ruby
# Database storage
A2A.configure do |config|
  config.storage_backend = :database
  config.database_url = ENV['DATABASE_URL']
end

# Redis storage  
A2A.configure do |config|
  config.storage_backend = :redis
  config.redis_url = ENV['REDIS_URL']
end
```

### How do I enable metrics and monitoring?

```ruby
A2A.configure do |config|
  config.enable_metrics = true
  config.metrics_backend = :prometheus  # or :statsd
  config.enable_health_checks = true
end

# Access metrics endpoint
GET /a2a/health
GET /a2a/metrics
```

## Testing

### How do I test A2A agents?

```ruby
# spec/support/a2a_helpers.rb
RSpec.configure do |config|
  config.include A2AHelpers
end

# In your tests
describe MyAgent do
  it "handles greetings" do
    agent = MyAgent.new
    
    request = build_json_rpc_request("greet", { name: "Alice" })
    response = agent.handle_a2a_request(request)
    
    expect(response['result']['message']).to eq("Hello, Alice!")
  end
end
```

### How do I mock A2A clients?

```ruby
# Create test double
client = instance_double(A2A::Client::HttpClient)
allow(client).to receive(:send_message).and_return(mock_message)

# Or use built-in helpers
client = mock_a2a_client(
  send_message: build_a2a_message(text: "response"),
  get_task: build_a2a_task(state: "completed")
)
```

### How do I test streaming responses?

```ruby
it "handles streaming responses" do
  responses = []
  
  client.send_message(message) do |response|
    responses << response
  end
  
  expect(responses).to include(
    an_instance_of(A2A::Types::TaskStatusUpdateEvent),
    an_instance_of(A2A::Types::Message)
  )
end
```

## Performance and Production

### How do I optimize performance?

```ruby
# Connection pooling
client = A2A::Client::HttpClient.new(url) do |conn|
  conn.adapter :net_http_persistent
end

# Streaming for large responses
client.send_message(message, streaming: true) do |chunk|
  process_incrementally(chunk)
end

# Limit message history
task = client.get_task(task_id, history_length: 10)
```

### How do I handle errors in production?

```ruby
begin
  response = client.send_message(message)
rescue A2A::Errors::HTTPError => e
  # Network/HTTP errors
  logger.error "A2A HTTP Error: #{e.message}"
  retry_with_backoff
rescue A2A::Errors::AuthenticationError => e
  # Auth errors
  refresh_credentials
  retry
rescue A2A::Errors::A2AError => e
  # Protocol errors
  logger.error "A2A Protocol Error: #{e.code} - #{e.message}"
  handle_protocol_error(e)
end
```

### What about security best practices?

```ruby
# Always use HTTPS in production
A2A.configure do |config|
  config.force_ssl = true
  config.ssl_verify = true
end

# Validate all inputs
a2a_method "process_data" do |params|
  # Validate parameters
  raise A2A::Errors::InvalidParams unless params[:data].is_a?(Hash)
  
  # Sanitize inputs
  clean_data = sanitize_input(params[:data])
  
  process(clean_data)
end

# Rate limiting
A2A.configure do |config|
  config.rate_limit_enabled = true
  config.rate_limit_requests = 100
  config.rate_limit_window = 60  # seconds
end
```

## Migration and Compatibility

### How do I migrate from the Python SDK?

The Ruby SDK maintains API compatibility with the Python SDK:

```python
# Python
from a2a import Client, Message, TextPart

client = Client("https://agent.example.com/a2a")
message = Message(
    message_id="123",
    role="user", 
    parts=[TextPart(text="Hello")]
)
response = client.send_message(message)
```

```ruby
# Ruby equivalent
require 'a2a'

client = A2A::Client::HttpClient.new("https://agent.example.com/a2a")
message = A2A::Types::Message.new(
  message_id: "123",
  role: "user",
  parts: [A2A::Types::TextPart.new(text: "Hello")]
)
response = client.send_message(message)
```

### Are there any breaking changes?

The Ruby SDK follows semantic versioning. Major version changes may include:

- Protocol version updates
- API signature changes
- Configuration format changes

Check the [CHANGELOG](../CHANGELOG.md) for details.

### How do I stay updated?

- Watch the [GitHub repository](https://github.com/a2aproject/a2a-ruby)
- Subscribe to [release notifications](https://github.com/a2aproject/a2a-ruby/releases)
- Follow the [A2A Protocol specification](https://github.com/google/a2a-protocol)

## Troubleshooting

### Common issues and solutions

See the [Troubleshooting Guide](troubleshooting.md) for detailed solutions to common problems.

### Getting help

- [GitHub Issues](https://github.com/a2aproject/a2a-ruby/issues) - Bug reports and feature requests
- [GitHub Discussions](https://github.com/a2aproject/a2a-ruby/discussions) - Questions and community help
- [API Documentation](https://rubydoc.info/gems/a2a-ruby) - Complete API reference

### Contributing

See [CONTRIBUTING.md](../CONTRIBUTING.md) for guidelines on:

- Reporting bugs
- Suggesting features  
- Submitting pull requests
- Development setup