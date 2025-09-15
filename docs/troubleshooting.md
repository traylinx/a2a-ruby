# Troubleshooting Guide

This guide helps you diagnose and resolve common issues when using the A2A Ruby SDK.

## Table of Contents

- [Connection Issues](#connection-issues)
- [Authentication Problems](#authentication-problems)
- [Protocol Errors](#protocol-errors)
- [Performance Issues](#performance-issues)
- [Rails Integration Issues](#rails-integration-issues)
- [Debugging Tools](#debugging-tools)
- [Common Error Codes](#common-error-codes)
- [FAQ](#faq)

## Connection Issues

### Cannot Connect to Agent

**Symptoms:**
- `A2A::Errors::HTTPError: Connection refused`
- `A2A::Errors::TimeoutError: Request timeout`

**Solutions:**

1. **Check the endpoint URL:**
```ruby
# Verify the URL is correct and accessible
client = A2A::Client::HttpClient.new("https://agent.example.com/a2a")

# Test basic connectivity
begin
  card = client.get_card
  puts "Connection successful"
rescue A2A::Errors::HTTPError => e
  puts "Connection failed: #{e.message}"
end
```

2. **Verify SSL certificates:**
```ruby
# For development, you might need to disable SSL verification
require 'faraday'

client = A2A::Client::HttpClient.new("https://localhost:3000/a2a") do |conn|
  conn.ssl.verify = false  # Only for development!
end
```

3. **Check firewall and network settings:**
```bash
# Test basic connectivity
curl -v https://agent.example.com/a2a/agent-card

# Check DNS resolution
nslookup agent.example.com
```

### Timeout Issues

**Symptoms:**
- Requests taking too long
- `A2A::Errors::TimeoutError`

**Solutions:**

1. **Increase timeout:**
```ruby
config = A2A::Client::Config.new
config.timeout = 120  # 2 minutes

client = A2A::Client::HttpClient.new(url, config: config)
```

2. **Use streaming for long operations:**
```ruby
# Instead of blocking calls, use streaming
client.send_message(message) do |response|
  # Handle responses as they arrive
  puts "Received: #{response}"
end
```

3. **Implement retry logic:**
```ruby
require 'retries'

with_retries(max_tries: 3, base_sleep_seconds: 1, max_sleep_seconds: 5) do
  client.send_message(message)
end
```

## Authentication Problems

### Invalid Credentials

**Symptoms:**
- `A2A::Errors::AuthenticationError: Invalid credentials`
- HTTP 401 Unauthorized responses

**Solutions:**

1. **Verify OAuth 2.0 configuration:**
```ruby
auth = A2A::Client::Auth::OAuth2.new(
  client_id: ENV['A2A_CLIENT_ID'],
  client_secret: ENV['A2A_CLIENT_SECRET'],
  token_url: "https://auth.example.com/oauth/token"
)

# Test token acquisition
begin
  token = auth.get_token
  puts "Token acquired: #{token[0..20]}..."
rescue => e
  puts "Token error: #{e.message}"
end
```

2. **Check JWT token validity:**
```ruby
require 'jwt'

token = "your-jwt-token"
begin
  payload = JWT.decode(token, nil, false)  # Don't verify for debugging
  puts "Token payload: #{payload}"
  puts "Expires at: #{Time.at(payload[0]['exp'])}"
rescue JWT::DecodeError => e
  puts "Invalid JWT: #{e.message}"
end
```

3. **Verify API key configuration:**
```ruby
auth = A2A::Client::Auth::ApiKey.new(
  key: ENV['A2A_API_KEY'],
  header: "X-API-Key"  # or parameter: "api_key"
)

# Test with debug logging
A2A.configure { |c| c.log_level = :debug }
client = A2A::Client::HttpClient.new(url, auth: auth)
```

### Token Expiration

**Symptoms:**
- Authentication works initially, then fails
- `A2A::Errors::AuthenticationError: Token expired`

**Solutions:**

1. **Implement automatic token refresh:**
```ruby
class RefreshableAuth < A2A::Client::Auth::OAuth2
  def apply_auth(request)
    if token_expired?
      refresh_token!
    end
    super
  end
  
  private
  
  def token_expired?
    @token_expires_at && Time.current >= @token_expires_at
  end
  
  def refresh_token!
    @token, @token_expires_at = get_token
  end
end
```

2. **Handle auth errors gracefully:**
```ruby
begin
  response = client.send_message(message)
rescue A2A::Errors::AuthenticationError
  # Refresh credentials and retry
  client.auth.refresh!
  response = client.send_message(message)
end
```

## Protocol Errors

### Invalid JSON-RPC Format

**Symptoms:**
- `A2A::Errors::InvalidRequest: Invalid JSON-RPC format`
- `A2A::Errors::ParseError: Invalid JSON`

**Solutions:**

1. **Validate message structure:**
```ruby
message = A2A::Types::Message.new(
  message_id: SecureRandom.uuid,  # Required
  role: "user",                   # Required: "user" or "agent"
  parts: [                        # Required: array of parts
    A2A::Types::TextPart.new(text: "Hello")
  ]
)

# Validate before sending
if message.valid?
  client.send_message(message)
else
  puts "Invalid message: #{message.errors.full_messages}"
end
```

2. **Check JSON-RPC request format:**
```ruby
# Manual JSON-RPC request (for debugging)
request = {
  jsonrpc: "2.0",     # Required
  method: "message/send",  # Required
  params: message.to_h,    # Optional
  id: 1               # Required for requests (omit for notifications)
}
```

### Method Not Found

**Symptoms:**
- `A2A::Errors::MethodNotFound: Method 'xyz' not found`

**Solutions:**

1. **Check agent card for available methods:**
```ruby
card = client.get_card
puts "Available capabilities:"
card.capabilities.each do |capability|
  puts "- #{capability.name}: #{capability.description}"
end
```

2. **Verify method name spelling:**
```ruby
# Standard A2A methods
valid_methods = [
  "message/send",
  "message/stream", 
  "tasks/get",
  "tasks/cancel",
  "tasks/resubscribe",
  "tasks/pushNotificationConfig/set",
  "tasks/pushNotificationConfig/get",
  "tasks/pushNotificationConfig/list",
  "tasks/pushNotificationConfig/delete",
  "agent/getAuthenticatedExtendedCard"
]
```

### Task Errors

**Symptoms:**
- `A2A::Errors::TaskNotFound: Task not found`
- `A2A::Errors::TaskNotCancelable: Task cannot be canceled`

**Solutions:**

1. **Check task status before operations:**
```ruby
begin
  task = client.get_task(task_id)
  puts "Task state: #{task.status.state}"
  
  if task.status.state.in?(['submitted', 'working'])
    client.cancel_task(task_id)
  else
    puts "Task cannot be canceled (state: #{task.status.state})"
  end
rescue A2A::Errors::TaskNotFound
  puts "Task #{task_id} not found"
end
```

2. **Handle task lifecycle properly:**
```ruby
# Valid task states
CANCELABLE_STATES = ['submitted', 'working'].freeze
FINAL_STATES = ['completed', 'canceled', 'failed', 'rejected'].freeze

def can_cancel_task?(task)
  CANCELABLE_STATES.include?(task.status.state)
end

def task_finished?(task)
  FINAL_STATES.include?(task.status.state)
end
```

## Performance Issues

### Slow Response Times

**Symptoms:**
- Requests taking longer than expected
- High memory usage

**Solutions:**

1. **Enable connection pooling:**
```ruby
require 'faraday/net_http_persistent'

client = A2A::Client::HttpClient.new(url) do |conn|
  conn.adapter :net_http_persistent
end
```

2. **Use streaming for large responses:**
```ruby
# Instead of loading everything into memory
client.send_message(message, streaming: true) do |chunk|
  process_chunk(chunk)  # Process incrementally
end
```

3. **Monitor performance:**
```ruby
A2A.configure do |config|
  config.enable_metrics = true
  config.log_level = :info
end

# Add custom timing
start_time = Time.current
response = client.send_message(message)
duration = Time.current - start_time
puts "Request took #{duration}s"
```

### Memory Leaks

**Symptoms:**
- Increasing memory usage over time
- Out of memory errors

**Solutions:**

1. **Properly close streaming connections:**
```ruby
enumerator = client.send_message(message)
begin
  enumerator.each do |response|
    process_response(response)
  end
ensure
  enumerator.close if enumerator.respond_to?(:close)
end
```

2. **Limit message history:**
```ruby
# When getting tasks, limit history
task = client.get_task(task_id, history_length: 10)
```

3. **Use object pooling for frequent operations:**
```ruby
class MessagePool
  def initialize
    @pool = []
  end
  
  def get_message
    @pool.pop || A2A::Types::Message.allocate
  end
  
  def return_message(message)
    message.reset!
    @pool.push(message) if @pool.size < 100
  end
end
```

## Rails Integration Issues

### Routes Not Working

**Symptoms:**
- 404 errors for A2A endpoints
- Routes not appearing in `rails routes`

**Solutions:**

1. **Verify engine mounting:**
```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount A2A::Engine => "/a2a"
end
```

2. **Check route generation:**
```bash
rails routes | grep a2a
# Should show:
# POST /a2a/rpc
# GET  /a2a/agent-card
# GET  /a2a/capabilities
```

3. **Verify controller inclusion:**
```ruby
class MyAgentController < ApplicationController
  include A2A::Rails::ControllerHelpers  # Required
  
  # Your A2A methods here
end
```

### Database Issues

**Symptoms:**
- Task storage errors
- Migration failures

**Solutions:**

1. **Run A2A migrations:**
```bash
rails generate a2a:migration
rails db:migrate
```

2. **Check database configuration:**
```ruby
# config/initializers/a2a.rb
A2A.configure do |config|
  config.storage_backend = :database  # or :memory, :redis
  config.database_url = ENV['DATABASE_URL']
end
```

3. **Verify model associations:**
```ruby
# Check if models are properly loaded
A2A::Server::Models::Task.first
A2A::Server::Models::PushNotificationConfig.first
```

## Debugging Tools

### Enable Debug Logging

```ruby
A2A.configure do |config|
  config.log_level = :debug
  config.log_requests = true
  config.log_responses = true
end
```

### Use the Console

```bash
# Rails console
rails console

# Gem console
cd a2a-ruby && bin/console
```

```ruby
# Test basic functionality
client = A2A::Client::HttpClient.new("http://localhost:3000/a2a")
card = client.get_card
puts JSON.pretty_generate(card.to_h)
```

### Network Debugging

```ruby
# Add request/response logging
require 'faraday/logging'

client = A2A::Client::HttpClient.new(url) do |conn|
  conn.response :logger, Rails.logger, bodies: true
end
```

### Performance Profiling

```ruby
require 'ruby-prof'

RubyProf.start
client.send_message(message)
result = RubyProf.stop

# Print results
printer = RubyProf::FlatPrinter.new(result)
printer.print(STDOUT)
```

## Common Error Codes

### JSON-RPC Standard Errors

| Code | Error | Description |
|------|-------|-------------|
| -32700 | Parse error | Invalid JSON |
| -32600 | Invalid Request | Invalid JSON-RPC format |
| -32601 | Method not found | Method doesn't exist |
| -32602 | Invalid params | Invalid method parameters |
| -32603 | Internal error | Server internal error |

### A2A-Specific Errors

| Code | Error | Description |
|------|-------|-------------|
| -32001 | Task not found | Task ID doesn't exist |
| -32002 | Task not cancelable | Task in non-cancelable state |
| -32003 | Invalid task state | Invalid state transition |
| -32004 | Authentication required | Auth needed for operation |
| -32005 | Insufficient permissions | User lacks required permissions |
| -32006 | Rate limit exceeded | Too many requests |
| -32007 | Invalid agent card | Agent card validation failed |
| -32008 | Transport not supported | Requested transport unavailable |
| -32009 | Invalid message format | Message doesn't match schema |
| -32010 | Service unavailable | Temporary service outage |

## FAQ

### Q: Why am I getting SSL certificate errors?

A: For development with self-signed certificates:

```ruby
# Disable SSL verification (development only!)
client = A2A::Client::HttpClient.new(url) do |conn|
  conn.ssl.verify = false
end

# Or set certificate bundle
client = A2A::Client::HttpClient.new(url) do |conn|
  conn.ssl.ca_file = '/path/to/ca-bundle.crt'
end
```

### Q: How do I handle network interruptions in streaming?

A: Implement reconnection logic:

```ruby
def stream_with_reconnect(client, message, max_retries: 3)
  retries = 0
  
  begin
    client.send_message(message) do |response|
      yield response
    end
  rescue A2A::Errors::HTTPError, A2A::Errors::TimeoutError => e
    retries += 1
    if retries <= max_retries
      sleep(2 ** retries)  # Exponential backoff
      retry
    else
      raise e
    end
  end
end
```

### Q: How do I test A2A agents in my test suite?

A: Use test doubles and helpers:

```ruby
# spec/support/a2a_helpers.rb
RSpec.configure do |config|
  config.include A2AHelpers
end

# In your tests
it "handles A2A messages" do
  message = build_a2a_message(text: "test")
  client = mock_a2a_client(send_message: mock_response)
  
  result = client.send_message(message)
  expect(result).to be_a(A2A::Types::Message)
end
```

### Q: Can I use A2A with other Ruby web frameworks?

A: Yes! The core SDK works with any Ruby application:

```ruby
# Sinatra example
require 'sinatra'
require 'a2a'

class MyAgent
  include A2A::Server::Agent
  # Define your methods
end

post '/a2a/rpc' do
  agent = MyAgent.new
  request_body = request.body.read
  
  json_rpc_request = A2A::Protocol::JsonRpc.parse_request(request_body)
  response = agent.handle_a2a_request(json_rpc_request)
  
  content_type :json
  response.to_json
end
```

### Q: How do I implement custom middleware?

A: Create middleware classes:

```ruby
class CustomLoggingMiddleware
  def initialize(app)
    @app = app
  end
  
  def call(request)
    start_time = Time.current
    
    response = @app.call(request)
    
    duration = Time.current - start_time
    Rails.logger.info "A2A Request: #{request.method} (#{duration}s)"
    
    response
  end
end

# Add to client
client.add_middleware(CustomLoggingMiddleware)
```

For more help:
- [GitHub Issues](https://github.com/a2aproject/a2a-ruby/issues)
- [Discussions](https://github.com/a2aproject/a2a-ruby/discussions)
- [API Documentation](https://rubydoc.info/gems/a2a-ruby)