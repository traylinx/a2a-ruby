# API Reference

This document provides a comprehensive reference for the A2A Ruby SDK API.

## Table of Contents

- [Client API](#client-api)
- [Server API](#server-api)
- [Types API](#types-api)
- [Configuration API](#configuration-api)
- [Transport API](#transport-api)
- [Authentication API](#authentication-api)
- [Error Handling](#error-handling)

## Client API

### A2A::Client::HttpClient

The primary client for communicating with A2A agents over HTTP.

#### Constructor

```ruby
client = A2A::Client::HttpClient.new(endpoint_url, **options)
```

**Parameters:**
- `endpoint_url` (String) - The A2A agent endpoint URL
- `options` (Hash) - Optional configuration
  - `:auth` (A2A::Client::Auth::Base) - Authentication strategy
  - `:config` (A2A::Client::Config) - Client configuration
  - `:middleware` (Array) - Middleware stack
  - `:consumers` (Array) - Event consumers

**Example:**
```ruby
auth = A2A::Client::Auth::OAuth2.new(
  client_id: "your-id",
  client_secret: "your-secret",
  token_url: "https://auth.example.com/token"
)

config = A2A::Client::Config.new
config.timeout = 60
config.streaming = true

client = A2A::Client::HttpClient.new(
  "https://agent.example.com/a2a",
  auth: auth,
  config: config
)
```

#### Methods

##### send_message(message, context: nil, &block)

Sends a message to the agent and handles responses.

**Parameters:**
- `message` (A2A::Types::Message) - The message to send
- `context` (Hash, optional) - Request context
- `&block` - Block to handle streaming responses

**Returns:**
- Single response (if not streaming)
- Enumerator (if streaming without block)
- Yields responses to block (if streaming with block)

**Example:**
```ruby
message = A2A::Types::Message.new(
  message_id: SecureRandom.uuid,
  role: "user",
  parts: [A2A::Types::TextPart.new(text: "Hello!")]
)

# Blocking call
response = client.send_message(message, streaming: false)

# Streaming with block
client.send_message(message) do |response|
  case response
  when A2A::Types::Message
    puts "Agent: #{response.parts.first.text}"
  when A2A::Types::TaskStatusUpdateEvent
    puts "Status: #{response.status.state}"
  end
end

# Streaming with enumerator
responses = client.send_message(message)
responses.each { |response| process(response) }
```

##### get_task(task_id, context: nil, history_length: nil)

Retrieves a task by ID.

**Parameters:**
- `task_id` (String) - The task ID
- `context` (Hash, optional) - Request context
- `history_length` (Integer, optional) - Limit message history

**Returns:**
- `A2A::Types::Task` - The task object

**Example:**
```ruby
task = client.get_task("task-123", history_length: 10)
puts "Task state: #{task.status.state}"
puts "Progress: #{task.status.progress}%" if task.status.progress
```

##### cancel_task(task_id, context: nil)

Cancels a task.

**Parameters:**
- `task_id` (String) - The task ID
- `context` (Hash, optional) - Request context

**Returns:**
- `A2A::Types::Task` - The updated task

**Example:**
```ruby
begin
  task = client.cancel_task("task-123")
  puts "Task canceled: #{task.status.state}"
rescue A2A::Errors::TaskNotCancelable => e
  puts "Cannot cancel task: #{e.message}"
end
```

##### resubscribe(task_id, context: nil, &block)

Resubscribes to task updates for streaming.

**Parameters:**
- `task_id` (String) - The task ID
- `context` (Hash, optional) - Request context
- `&block` - Block to handle events

**Example:**
```ruby
client.resubscribe("task-123") do |event|
  case event
  when A2A::Types::TaskStatusUpdateEvent
    puts "Status update: #{event.status.state}"
  when A2A::Types::TaskArtifactUpdateEvent
    puts "New artifact: #{event.artifact.name}"
  end
end
```

##### get_card(context: nil)

Retrieves the agent card.

**Parameters:**
- `context` (Hash, optional) - Request context

**Returns:**
- `A2A::Types::AgentCard` - The agent card

**Example:**
```ruby
card = client.get_card
puts "Agent: #{card.name} v#{card.version}"
puts "Skills: #{card.skills.map(&:name).join(', ')}"
```

##### set_task_callback(task_id, push_config, context: nil)

Sets up push notifications for a task.

**Parameters:**
- `task_id` (String) - The task ID
- `push_config` (A2A::Types::PushNotificationConfig) - Push notification configuration
- `context` (Hash, optional) - Request context

**Example:**
```ruby
push_config = A2A::Types::PushNotificationConfig.new(
  url: "https://your-app.com/webhooks/a2a",
  authentication: {
    type: "bearer",
    token: "webhook-secret"
  }
)

client.set_task_callback("task-123", push_config)
```

### A2A::Client::Config

Client configuration object.

#### Properties

```ruby
config = A2A::Client::Config.new

# Streaming configuration
config.streaming = true                    # Enable streaming responses
config.polling = false                     # Enable polling fallback

# Transport configuration  
config.supported_transports = ['JSONRPC']  # Supported transport protocols
config.use_client_preference = true        # Use client transport preference

# Timeout configuration
config.timeout = 30                        # Request timeout in seconds
config.connect_timeout = 10                # Connection timeout in seconds

# Output configuration
config.accepted_output_modes = ['text', 'structured']  # Accepted output modes

# Push notification configuration
config.push_notification_configs = []      # Default push notification configs
```

## Server API

### A2A::Server::Agent

Mixin for creating A2A agents.

#### Usage

```ruby
class MyAgent
  include A2A::Server::Agent
  
  # Agent configuration
  a2a_config(
    name: "My Agent",
    description: "A sample A2A agent",
    version: "1.0.0"
  )
  
  # Define skills
  a2a_skill "greeting" do |skill|
    skill.description = "Greet users"
    skill.tags = ["greeting", "conversation"]
    skill.examples = ["Hello", "Say hi"]
    skill.input_modes = ["text"]
    skill.output_modes = ["text"]
  end
  
  # Define methods
  a2a_method "greet" do |params|
    name = params[:name] || "there"
    { message: "Hello, #{name}!" }
  end
end
```

#### Class Methods

##### a2a_config(**options)

Configures the agent metadata.

**Parameters:**
- `name` (String) - Agent name
- `description` (String) - Agent description  
- `version` (String) - Agent version
- `url` (String, optional) - Agent URL
- `provider` (Hash, optional) - Provider information

##### a2a_skill(name, &block)

Defines an agent skill.

**Parameters:**
- `name` (String) - Skill name
- `&block` - Configuration block

**Block methods:**
- `description` (String) - Skill description
- `tags` (Array<String>) - Skill tags
- `examples` (Array<String>) - Usage examples
- `input_modes` (Array<String>) - Supported input modes
- `output_modes` (Array<String>) - Supported output modes
- `security` (Hash, optional) - Security requirements

##### a2a_method(name, **options, &block)

Defines an A2A method.

**Parameters:**
- `name` (String) - Method name
- `options` (Hash) - Method options
  - `:streaming` (Boolean) - Whether method supports streaming
  - `:auth_required` (Boolean) - Whether authentication is required
- `&block` - Method implementation

**Example:**
```ruby
# Simple method
a2a_method "get_weather" do |params|
  location = params[:location]
  WeatherService.current(location)
end

# Streaming method
a2a_method "weather_forecast", streaming: true do |params|
  Enumerator.new do |yielder|
    # Yield status updates
    yielder << task_status_update("working")
    
    # Yield data
    forecast_data.each do |day|
      message = A2A::Types::Message.new(
        message_id: SecureRandom.uuid,
        role: "agent",
        parts: [A2A::Types::TextPart.new(text: day.to_json)]
      )
      yielder << message
    end
    
    # Final status
    yielder << task_status_update("completed")
  end
end

# Method with authentication
a2a_method "secure_operation", auth_required: true do |params|
  # Access current user via @current_user (set by auth middleware)
  return { error: "Unauthorized" } unless @current_user
  
  perform_secure_operation(params, @current_user)
end
```

#### Instance Methods

##### handle_a2a_request(request)

Handles an A2A JSON-RPC request.

**Parameters:**
- `request` (A2A::Protocol::JsonRpc::Request) - The JSON-RPC request

**Returns:**
- Hash - JSON-RPC response

##### generate_agent_card(**overrides)

Generates an agent card from the agent definition.

**Parameters:**
- `overrides` (Hash) - Override default values

**Returns:**
- `A2A::Types::AgentCard` - The agent card

### A2A::Server::TaskManager

Manages task lifecycle and persistence.

#### Constructor

```ruby
task_manager = A2A::Server::TaskManager.new(storage: storage_backend)
```

#### Methods

##### create_task(type:, params: {}, **options)

Creates a new task.

**Parameters:**
- `type` (String) - Task type
- `params` (Hash) - Task parameters
- `options` (Hash) - Additional options

**Returns:**
- `A2A::Types::Task` - The created task

##### update_task_status(task_id, status)

Updates task status.

**Parameters:**
- `task_id` (String) - Task ID
- `status` (A2A::Types::TaskStatus) - New status

**Returns:**
- `A2A::Types::Task` - Updated task

##### get_task(task_id)

Retrieves a task.

**Parameters:**
- `task_id` (String) - Task ID

**Returns:**
- `A2A::Types::Task` - The task

**Raises:**
- `A2A::Errors::TaskNotFound` - If task doesn't exist

## Types API

### A2A::Types::Message

Represents an A2A message.

#### Constructor

```ruby
message = A2A::Types::Message.new(
  message_id: SecureRandom.uuid,
  role: "user",                    # "user" or "agent"
  parts: [part1, part2],          # Array of Part objects
  context_id: "context-123",       # Optional
  task_id: "task-123",            # Optional
  metadata: { key: "value" },     # Optional
  extensions: [],                 # Optional
  reference_task_ids: []          # Optional
)
```

#### Properties

- `message_id` (String) - Unique message identifier
- `role` (String) - Message role ("user" or "agent")
- `parts` (Array<A2A::Types::Part>) - Message parts
- `context_id` (String, optional) - Context identifier
- `task_id` (String, optional) - Associated task ID
- `kind` (String) - Always "message"
- `metadata` (Hash, optional) - Additional metadata
- `extensions` (Array, optional) - Protocol extensions
- `reference_task_ids` (Array<String>, optional) - Referenced task IDs

### A2A::Types::Part

Base class for message parts. Use specific subclasses:

#### A2A::Types::TextPart

```ruby
text_part = A2A::Types::TextPart.new(
  text: "Hello, world!",
  metadata: { language: "en" }  # Optional
)
```

#### A2A::Types::FilePart

```ruby
# File with bytes (base64 encoded)
file_part = A2A::Types::FilePart.new(
  file: A2A::Types::FileWithBytes.new(
    name: "document.pdf",
    mime_type: "application/pdf",
    bytes: Base64.encode64(file_content)
  )
)

# File with URI reference
file_part = A2A::Types::FilePart.new(
  file: A2A::Types::FileWithUri.new(
    name: "document.pdf", 
    mime_type: "application/pdf",
    uri: "https://storage.example.com/document.pdf"
  )
)
```

#### A2A::Types::DataPart

```ruby
data_part = A2A::Types::DataPart.new(
  data: { key: "value", numbers: [1, 2, 3] },
  metadata: { format: "json" }
)
```

### A2A::Types::Task

Represents a task with lifecycle management.

#### Constructor

```ruby
task = A2A::Types::Task.new(
  id: SecureRandom.uuid,
  context_id: SecureRandom.uuid,
  status: A2A::Types::TaskStatus.new(state: "submitted"),
  artifacts: [],                   # Optional
  history: [],                     # Optional
  metadata: {}                     # Optional
)
```

#### Properties

- `id` (String) - Unique task identifier
- `context_id` (String) - Context identifier
- `status` (A2A::Types::TaskStatus) - Current task status
- `kind` (String) - Always "task"
- `artifacts` (Array<A2A::Types::Artifact>, optional) - Task artifacts
- `history` (Array<A2A::Types::Message>, optional) - Message history
- `metadata` (Hash, optional) - Additional metadata

### A2A::Types::TaskStatus

Represents task status and progress.

#### Constructor

```ruby
status = A2A::Types::TaskStatus.new(
  state: "working",                    # Required
  message: "Processing data...",       # Optional
  progress: 75,                       # Optional (0-100)
  result: { processed: 1000 },        # Optional
  error: { message: "Error occurred" }, # Optional
  updated_at: Time.current.iso8601    # Optional
)
```

#### Valid States

- `submitted` - Task created, waiting to start
- `working` - Task in progress
- `input-required` - Task needs user input
- `completed` - Task finished successfully
- `canceled` - Task was canceled
- `failed` - Task failed with error
- `rejected` - Task rejected (invalid params, etc.)
- `auth-required` - Task needs authentication
- `unknown` - Unknown state

### A2A::Types::AgentCard

Represents agent capabilities and metadata.

#### Constructor

```ruby
card = A2A::Types::AgentCard.new(
  name: "Weather Agent",
  description: "Provides weather information",
  version: "1.0.0",
  url: "https://agent.example.com/a2a",
  preferred_transport: "JSONRPC",
  skills: [skill1, skill2],
  capabilities: capabilities,
  default_input_modes: ["text"],
  default_output_modes: ["text", "structured"],
  additional_interfaces: [interface1],     # Optional
  security: security_config,               # Optional
  security_schemes: [scheme1],            # Optional
  provider: provider_info,                # Optional
  protocol_version: "0.3.0",             # Optional
  supports_authenticated_extended_card: true, # Optional
  signatures: [signature1],               # Optional
  documentation_url: "https://docs.example.com", # Optional
  icon_url: "https://example.com/icon.png" # Optional
)
```

## Configuration API

### A2A.configure

Global configuration method.

```ruby
A2A.configure do |config|
  # Protocol configuration
  config.protocol_version = "0.3.0"
  config.default_transport = "JSONRPC"
  
  # Feature flags
  config.streaming_enabled = true
  config.push_notifications_enabled = true
  
  # Timeouts
  config.default_timeout = 30
  config.connect_timeout = 10
  
  # Logging
  config.log_level = :info
  config.log_requests = false
  config.log_responses = false
  
  # Storage
  config.storage_backend = :database  # :memory, :redis, :database
  config.database_url = ENV['DATABASE_URL']
  config.redis_url = ENV['REDIS_URL']
  
  # Security
  config.force_ssl = true
  config.ssl_verify = true
  
  # Performance
  config.enable_metrics = true
  config.metrics_backend = :prometheus  # :prometheus, :statsd
  
  # Rate limiting
  config.rate_limit_enabled = true
  config.rate_limit_requests = 100
  config.rate_limit_window = 60
end
```

## Transport API

### A2A::Transport::Http

HTTP transport implementation using Faraday.

```ruby
transport = A2A::Transport::Http.new(
  endpoint_url: "https://agent.example.com/a2a",
  timeout: 30,
  ssl_verify: true
)

response = transport.send_request(json_rpc_request)
```

### A2A::Transport::SSE

Server-Sent Events transport for streaming.

```ruby
sse = A2A::Transport::SSE.new(endpoint_url)

sse.stream(request) do |event|
  case event.type
  when 'message'
    handle_message(JSON.parse(event.data))
  when 'error'
    handle_error(JSON.parse(event.data))
  end
end
```

## Authentication API

### A2A::Client::Auth::OAuth2

OAuth 2.0 client credentials flow.

```ruby
auth = A2A::Client::Auth::OAuth2.new(
  client_id: "your-client-id",
  client_secret: "your-client-secret",
  token_url: "https://auth.example.com/oauth/token",
  scope: "a2a:read a2a:write"  # Optional
)

# Manual token acquisition
token, expires_at = auth.get_token

# Automatic application to requests
client = A2A::Client::HttpClient.new(url, auth: auth)
```

### A2A::Client::Auth::JWT

JWT bearer token authentication.

```ruby
auth = A2A::Client::Auth::JWT.new(
  token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  header: "Authorization"  # Optional, defaults to "Authorization"
)
```

### A2A::Client::Auth::ApiKey

API key authentication.

```ruby
# Header-based API key
auth = A2A::Client::Auth::ApiKey.new(
  key: "your-api-key",
  header: "X-API-Key"
)

# Query parameter API key
auth = A2A::Client::Auth::ApiKey.new(
  key: "your-api-key", 
  parameter: "api_key"
)
```

### Custom Authentication

```ruby
class CustomAuth < A2A::Client::Auth::Base
  def initialize(credentials)
    @credentials = credentials
  end
  
  def apply_auth(request)
    # Add custom authentication to request
    request.headers['X-Custom-Auth'] = generate_signature(@credentials)
  end
  
  private
  
  def generate_signature(credentials)
    # Custom signature logic
  end
end
```

## Error Handling

### Exception Hierarchy

```
A2A::Errors::A2AError
├── A2A::Errors::ParseError (-32700)
├── A2A::Errors::InvalidRequest (-32600)
├── A2A::Errors::MethodNotFound (-32601)
├── A2A::Errors::InvalidParams (-32602)
├── A2A::Errors::InternalError (-32603)
├── A2A::Errors::TaskNotFound (-32001)
├── A2A::Errors::TaskNotCancelable (-32002)
├── A2A::Errors::InvalidTaskState (-32003)
├── A2A::Errors::AuthenticationRequired (-32004)
├── A2A::Errors::InsufficientPermissions (-32005)
├── A2A::Errors::RateLimitExceeded (-32006)
├── A2A::Errors::InvalidAgentCard (-32007)
├── A2A::Errors::TransportNotSupported (-32008)
├── A2A::Errors::InvalidMessageFormat (-32009)
├── A2A::Errors::ServiceUnavailable (-32010)
├── A2A::Errors::ClientError
│   ├── A2A::Errors::HTTPError
│   ├── A2A::Errors::TimeoutError
│   └── A2A::Errors::AuthenticationError
└── A2A::Errors::ServerError
```

### Error Handling Patterns

```ruby
begin
  response = client.send_message(message)
rescue A2A::Errors::AuthenticationError => e
  # Handle auth errors
  refresh_credentials
  retry
rescue A2A::Errors::TaskNotFound => e
  # Handle missing task
  logger.warn "Task not found: #{e.message}"
rescue A2A::Errors::RateLimitExceeded => e
  # Handle rate limiting
  sleep(e.retry_after || 60)
  retry
rescue A2A::Errors::A2AError => e
  # Handle all A2A protocol errors
  logger.error "A2A Error #{e.code}: #{e.message}"
  handle_protocol_error(e)
rescue StandardError => e
  # Handle unexpected errors
  logger.error "Unexpected error: #{e.message}"
  raise
end
```

### Error Response Format

A2A errors include structured information:

```ruby
begin
  client.send_message(message)
rescue A2A::Errors::A2AError => e
  puts "Error Code: #{e.code}"
  puts "Message: #{e.message}"
  puts "Data: #{e.data}" if e.data
  
  # Convert to JSON-RPC error format
  json_rpc_error = e.to_json_rpc_error
  # => { code: -32001, message: "Task not found", data: {...} }
end
```

For complete API documentation with examples, see the [YARD documentation](https://rubydoc.info/gems/a2a-ruby).