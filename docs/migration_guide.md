# Migration Guide

This guide helps you migrate to the A2A Ruby SDK from other A2A implementations or similar agent communication libraries.

## Table of Contents

- [Migrating from Python A2A SDK](#migrating-from-python-a2a-sdk)
- [Migrating from JavaScript A2A SDK](#migrating-from-javascript-a2a-sdk)
- [Migrating from Custom JSON-RPC](#migrating-from-custom-json-rpc)
- [Migrating from gRPC](#migrating-from-grpc)
- [Configuration Migration](#configuration-migration)
- [Common Patterns](#common-patterns)
- [Breaking Changes](#breaking-changes)

## Migrating from Python A2A SDK

The Ruby SDK maintains API compatibility with the Python SDK, making migration straightforward.

### Client Migration

**Python:**
```python
from a2a import Client, Message, TextPart
from a2a.auth import OAuth2Auth

# Create client with auth
auth = OAuth2Auth(
    client_id="your-id",
    client_secret="your-secret",
    token_url="https://auth.example.com/token"
)

client = Client("https://agent.example.com/a2a", auth=auth)

# Send message
message = Message(
    message_id="123",
    role="user",
    parts=[TextPart(text="Hello, agent!")]
)

for response in client.send_message(message):
    if isinstance(response, Message):
        print(f"Agent: {response.parts[0].text}")
```

**Ruby:**
```ruby
require 'a2a'

# Create client with auth
auth = A2A::Client::Auth::OAuth2.new(
  client_id: "your-id",
  client_secret: "your-secret", 
  token_url: "https://auth.example.com/token"
)

client = A2A::Client::HttpClient.new("https://agent.example.com/a2a", auth: auth)

# Send message
message = A2A::Types::Message.new(
  message_id: "123",
  role: "user",
  parts: [A2A::Types::TextPart.new(text: "Hello, agent!")]
)

client.send_message(message) do |response|
  if response.is_a?(A2A::Types::Message)
    puts "Agent: #{response.parts.first.text}"
  end
end
```

### Server Migration

**Python:**
```python
from a2a.server import Agent, a2a_method, a2a_skill

class WeatherAgent(Agent):
    @a2a_skill(
        name="weather_lookup",
        description="Get weather information",
        tags=["weather", "information"]
    )
    @a2a_method("get_weather")
    def get_weather(self, params):
        location = params.get("location", "Unknown")
        return {
            "location": location,
            "temperature": "72°F",
            "condition": "Sunny"
        }
    
    @a2a_method("weather_stream", streaming=True)
    def weather_stream(self, params):
        for i in range(5):
            yield TaskStatusUpdateEvent(
                task_id=params["task_id"],
                status=TaskStatus(state="working", progress=i*20)
            )
            yield Message(
                message_id=str(uuid.uuid4()),
                role="agent",
                parts=[TextPart(text=f"Day {i+1} forecast")]
            )
```

**Ruby:**
```ruby
class WeatherAgent
  include A2A::Server::Agent
  
  a2a_skill "weather_lookup" do |skill|
    skill.description = "Get weather information"
    skill.tags = ["weather", "information"]
  end
  
  a2a_method "get_weather" do |params|
    location = params[:location] || "Unknown"
    {
      location: location,
      temperature: "72°F", 
      condition: "Sunny"
    }
  end
  
  a2a_method "weather_stream", streaming: true do |params|
    Enumerator.new do |yielder|
      5.times do |i|
        yielder << A2A::Types::TaskStatusUpdateEvent.new(
          task_id: params[:task_id],
          context_id: params[:context_id],
          status: A2A::Types::TaskStatus.new(state: "working", progress: i*20)
        )
        yielder << A2A::Types::Message.new(
          message_id: SecureRandom.uuid,
          role: "agent",
          parts: [A2A::Types::TextPart.new(text: "Day #{i+1} forecast")]
        )
      end
    end
  end
end
```

### Key Differences

| Aspect | Python | Ruby |
|--------|--------|------|
| Module structure | `from a2a import Client` | `require 'a2a'` |
| Class naming | `Client` | `A2A::Client::HttpClient` |
| Method calls | `client.send_message()` | `client.send_message()` |
| Iteration | `for response in client.send_message()` | `client.send_message() do |response|` |
| Type checking | `isinstance(response, Message)` | `response.is_a?(A2A::Types::Message)` |
| Decorators | `@a2a_method` | `a2a_method` block |
| Generators | `yield response` | `yielder << response` |

## Migrating from JavaScript A2A SDK

**JavaScript:**
```javascript
import { Client, Message, TextPart } from '@a2a/client';

const client = new Client('https://agent.example.com/a2a');

const message = new Message({
  messageId: '123',
  role: 'user',
  parts: [new TextPart({ text: 'Hello!' })]
});

for await (const response of client.sendMessage(message)) {
  if (response instanceof Message) {
    console.log(`Agent: ${response.parts[0].text}`);
  }
}
```

**Ruby:**
```ruby
require 'a2a'

client = A2A::Client::HttpClient.new('https://agent.example.com/a2a')

message = A2A::Types::Message.new(
  message_id: '123',
  role: 'user',
  parts: [A2A::Types::TextPart.new(text: 'Hello!')]
)

client.send_message(message) do |response|
  if response.is_a?(A2A::Types::Message)
    puts "Agent: #{response.parts.first.text}"
  end
end
```

### Key Differences

| Aspect | JavaScript | Ruby |
|--------|------------|------|
| Imports | `import { Client }` | `require 'a2a'` |
| Constructor | `new Client()` | `A2A::Client::HttpClient.new()` |
| Async iteration | `for await (const response of ...)` | `client.send_message() do |response|` |
| Property access | `response.parts[0].text` | `response.parts.first.text` |
| Naming convention | camelCase | snake_case |

## Migrating from Custom JSON-RPC

If you have a custom JSON-RPC implementation, here's how to migrate:

**Custom JSON-RPC:**
```ruby
require 'net/http'
require 'json'

def send_rpc_request(method, params)
  request = {
    jsonrpc: '2.0',
    method: method,
    params: params,
    id: 1
  }
  
  uri = URI('https://agent.example.com/rpc')
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  
  response = http.post(uri.path, request.to_json, {
    'Content-Type' => 'application/json'
  })
  
  JSON.parse(response.body)
end

# Send message
result = send_rpc_request('message/send', {
  message: {
    messageId: '123',
    role: 'user',
    parts: [{ kind: 'text', text: 'Hello!' }]
  }
})
```

**A2A Ruby SDK:**
```ruby
require 'a2a'

client = A2A::Client::HttpClient.new('https://agent.example.com/a2a')

message = A2A::Types::Message.new(
  message_id: '123',
  role: 'user',
  parts: [A2A::Types::TextPart.new(text: 'Hello!')]
)

client.send_message(message) do |response|
  # Handle typed responses
  case response
  when A2A::Types::Message
    puts "Message: #{response.parts.first.text}"
  when A2A::Types::Task
    puts "Task created: #{response.id}"
  end
end
```

### Benefits of Migration

- **Type Safety**: Structured types instead of raw hashes
- **Error Handling**: Proper exception hierarchy
- **Authentication**: Built-in auth strategies
- **Streaming**: Native streaming support
- **Agent Cards**: Automatic capability discovery
- **Task Management**: Built-in task lifecycle

## Migrating from gRPC

**Custom gRPC:**
```ruby
require 'grpc'
require 'agent_services_pb'

stub = Agent::AgentService::Stub.new('agent.example.com:443', :this_channel_is_insecure)

request = Agent::MessageRequest.new(
  message: Agent::Message.new(
    message_id: '123',
    role: 'USER',
    parts: [Agent::Part.new(text: Agent::TextPart.new(text: 'Hello!'))]
  )
)

response = stub.send_message(request)
```

**A2A Ruby SDK:**
```ruby
require 'a2a'

# A2A SDK handles transport negotiation automatically
client = A2A::Client::HttpClient.new('https://agent.example.com/a2a')

message = A2A::Types::Message.new(
  message_id: '123',
  role: 'user',
  parts: [A2A::Types::TextPart.new(text: 'Hello!')]
)

# SDK will use gRPC if available and preferred
client.send_message(message) do |response|
  puts response
end
```

### Transport Configuration

```ruby
# Prefer gRPC when available
config = A2A::Client::Config.new
config.supported_transports = ['GRPC', 'JSONRPC']
config.use_client_preference = true

client = A2A::Client::HttpClient.new(url, config: config)
```

## Configuration Migration

### Environment Variables

**Before:**
```bash
# Custom configuration
AGENT_ENDPOINT=https://agent.example.com/rpc
AGENT_TIMEOUT=30
AGENT_AUTH_TOKEN=abc123
```

**After:**
```bash
# A2A configuration
A2A_ENDPOINT=https://agent.example.com/a2a
A2A_TIMEOUT=30
A2A_AUTH_TYPE=bearer
A2A_AUTH_TOKEN=abc123
A2A_PROTOCOL_VERSION=0.3.0
```

### Configuration Files

**Before:**
```yaml
# config/agent.yml
endpoint: https://agent.example.com/rpc
timeout: 30
auth:
  type: token
  token: abc123
```

**After:**
```ruby
# config/initializers/a2a.rb
A2A.configure do |config|
  config.default_endpoint = ENV['A2A_ENDPOINT']
  config.default_timeout = ENV['A2A_TIMEOUT']&.to_i || 30
  config.protocol_version = '0.3.0'
  config.streaming_enabled = true
end
```

## Common Patterns

### Error Handling Migration

**Before:**
```ruby
begin
  response = send_request(data)
  if response['error']
    handle_error(response['error'])
  else
    process_result(response['result'])
  end
rescue Net::TimeoutError => e
  retry_request
rescue JSON::ParserError => e
  handle_parse_error(e)
end
```

**After:**
```ruby
begin
  client.send_message(message) do |response|
    process_response(response)
  end
rescue A2A::Errors::TimeoutError => e
  retry_with_backoff
rescue A2A::Errors::ParseError => e
  handle_parse_error(e)
rescue A2A::Errors::AuthenticationError => e
  refresh_credentials
  retry
end
```

### Async Processing Migration

**Before:**
```ruby
# Custom background job
class ProcessMessageJob < ApplicationJob
  def perform(message_data)
    # Manual JSON-RPC call
    response = send_rpc_request('process', message_data)
    
    # Manual status tracking
    update_status(message_data['id'], 'completed')
  end
end
```

**After:**
```ruby
# A2A agent method
a2a_method "process_message" do |params|
  # Create task automatically
  task = create_task(type: "message_processing", params: params)
  
  # Background processing
  ProcessMessageJob.perform_later(task.id, params)
  
  # Return task immediately
  task
end

class ProcessMessageJob < ApplicationJob
  def perform(task_id, params)
    task_manager = A2A::Server::TaskManager.new
    
    # Automatic status updates
    task_manager.update_task_status(task_id, 
      A2A::Types::TaskStatus.new(state: "working")
    )
    
    # Process...
    result = process_data(params)
    
    # Complete task
    task_manager.update_task_status(task_id,
      A2A::Types::TaskStatus.new(state: "completed", result: result)
    )
  end
end
```

### Authentication Migration

**Before:**
```ruby
class CustomAuth
  def initialize(token)
    @token = token
  end
  
  def add_headers(headers)
    headers['Authorization'] = "Bearer #{@token}"
  end
end
```

**After:**
```ruby
# Use built-in auth
auth = A2A::Client::Auth::JWT.new(token: @token)
client = A2A::Client::HttpClient.new(url, auth: auth)

# Or create custom auth
class CustomAuth < A2A::Client::Auth::Base
  def initialize(token)
    @token = token
  end
  
  def apply_auth(request)
    request.headers['Authorization'] = "Bearer #{@token}"
  end
end
```

## Breaking Changes

### Version 1.0 to 2.0

- **Configuration**: New configuration format
- **Types**: Stricter type validation
- **Authentication**: New auth interface

### Version 0.x to 1.0

- **Protocol**: Updated to A2A Protocol v0.3.0
- **API**: Standardized method names
- **Transport**: Added gRPC support

### Migration Checklist

- [ ] Update gem version in Gemfile
- [ ] Update configuration format
- [ ] Replace custom JSON-RPC with A2A types
- [ ] Update error handling
- [ ] Test authentication flows
- [ ] Verify agent card generation
- [ ] Update tests with new helpers
- [ ] Review performance implications

### Gradual Migration Strategy

1. **Phase 1**: Install A2A SDK alongside existing code
2. **Phase 2**: Migrate client calls one endpoint at a time
3. **Phase 3**: Migrate server endpoints to A2A agents
4. **Phase 4**: Remove legacy code and dependencies

### Testing Migration

```ruby
# Test both old and new implementations
describe "Migration compatibility" do
  it "produces same results" do
    # Old implementation
    old_result = legacy_client.send_message(message_data)
    
    # New implementation  
    message = A2A::Types::Message.new(
      message_id: message_data[:id],
      role: message_data[:role],
      parts: [A2A::Types::TextPart.new(text: message_data[:text])]
    )
    new_result = a2a_client.send_message(message)
    
    # Compare results
    expect(normalize_result(new_result)).to eq(normalize_result(old_result))
  end
end
```

## Getting Help

- [GitHub Issues](https://github.com/a2aproject/a2a-ruby/issues) - Report migration issues
- [Discussions](https://github.com/a2aproject/a2a-ruby/discussions) - Ask migration questions
- [Examples](https://github.com/a2aproject/a2a-ruby-examples) - See migration examples

For complex migrations, consider:
- Creating a migration plan
- Running both systems in parallel
- Gradual rollout with feature flags
- Comprehensive testing at each phase