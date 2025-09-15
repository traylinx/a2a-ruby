# Server Applications

The A2A Ruby SDK provides ready-to-use server applications that can be deployed with popular Ruby web frameworks. These applications handle all the A2A protocol details, allowing you to focus on your agent logic.

## Overview

The SDK includes two main server application types:

- **RackApp**: A Rack-compatible application that works with any Rack server
- **SinatraApp**: A Sinatra-based application with Ruby-idiomatic routing

Both applications provide:
- Agent card serving at `/.well-known/a2a/agent-card`
- Extended agent card serving at `/a2a/agent-card/extended`
- JSON-RPC endpoint at `/a2a/rpc`
- Server-Sent Events for streaming responses
- Proper error handling and response formatting

## Rack Application

### Basic Setup

```ruby
require 'a2a'

# Create agent card
agent_card = A2A::Types::AgentCard.new(
  name: "My Agent",
  description: "A helpful agent",
  version: "1.0.0",
  capabilities: A2A::Types::Capabilities.new(
    streaming: true,
    push_notifications: true,
    task_management: true
  )
)

# Create agent executor
class MyAgentExecutor < A2A::Server::AgentExecution::SimpleAgentExecutor
  def process_message(message, task, context)
    text = message.parts.first.text
    { response: "You said: #{text}" }
  end
end

# Create request handler
executor = MyAgentExecutor.new
handler = A2A::Server::DefaultRequestHandler.new(executor)

# Create Rack application
app = A2A::Server::Apps::RackApp.new(
  agent_card: agent_card,
  request_handler: handler
)

# Run with any Rack server
# rackup -p 9292
```

### Advanced Configuration

```ruby
app = A2A::Server::Apps::RackApp.new(
  agent_card: agent_card,
  request_handler: handler,
  extended_agent_card: extended_card,  # Optional extended card
  card_modifier: ->(card) {
    # Dynamically modify the public card
    card.metadata ||= {}
    card.metadata[:server_time] = Time.now.utc.iso8601
    card.metadata[:ruby_version] = RUBY_VERSION
    card
  },
  extended_card_modifier: ->(card, context) {
    # Modify extended card based on context
    if context.authenticated?
      card.metadata ||= {}
      card.metadata[:user] = context.user.to_s
    end
    card
  }
)
```

### Deployment with config.ru

```ruby
# config.ru
require_relative 'my_agent'

# Add middleware
use Rack::Logger
use Rack::CommonLogger

# CORS for development
if ENV['RACK_ENV'] == 'development'
  use Rack::Cors do
    allow do
      origins '*'
      resource '*', 
        headers: :any, 
        methods: [:get, :post, :options]
    end
  end
end

# Authentication middleware (optional)
use MyAuthMiddleware

# Run the A2A app
run create_a2a_app
```

### Custom Middleware Integration

```ruby
class AuthenticationMiddleware
  def initialize(app)
    @app = app
  end
  
  def call(env)
    # Extract authentication from headers
    auth_header = env['HTTP_AUTHORIZATION']
    
    if auth_header&.start_with?('Bearer ')
      token = auth_header[7..-1]
      user = authenticate_token(token)
      env['current_user'] = user if user
    end
    
    @app.call(env)
  end
  
  private
  
  def authenticate_token(token)
    # Your authentication logic
    User.find_by_token(token)
  end
end

# Use with Rack app
use AuthenticationMiddleware
run app
```

## Sinatra Application

### Basic Setup

```ruby
require 'sinatra'
require 'a2a'

class MyA2AApp < A2A::Server::Apps::SinatraApp
  # Configure A2A components
  configure_a2a(
    agent_card: agent_card,
    request_handler: handler
  )
  
  # Add custom routes if needed
  get '/health' do
    { status: 'ok', timestamp: Time.now.utc.iso8601 }.to_json
  end
  
  # Custom error handling
  error A2A::Errors::AuthenticationRequired do
    status 401
    { error: 'Authentication required' }.to_json
  end
end

# Run the app
MyA2AApp.run! port: 9292
```

### Advanced Sinatra Integration

```ruby
class AdvancedA2AApp < A2A::Server::Apps::SinatraApp
  # Enable sessions for authentication
  enable :sessions
  
  # Configure A2A with dynamic card modification
  configure_a2a(
    agent_card: agent_card,
    request_handler: handler,
    card_modifier: method(:modify_public_card),
    extended_card_modifier: method(:modify_extended_card)
  )
  
  # Authentication helpers
  helpers do
    def current_user
      @current_user ||= User.find(session[:user_id]) if session[:user_id]
    end
    
    def authenticated?
      !current_user.nil?
    end
    
    def require_auth!
      halt 401, { error: 'Authentication required' }.to_json unless authenticated?
    end
  end
  
  # Authentication routes
  post '/auth/login' do
    user = User.authenticate(params[:username], params[:password])
    if user
      session[:user_id] = user.id
      { success: true, user: user.to_h }.to_json
    else
      status 401
      { error: 'Invalid credentials' }.to_json
    end
  end
  
  post '/auth/logout' do
    session.clear
    { success: true }.to_json
  end
  
  # Protected routes
  get '/admin/stats' do
    require_auth!
    content_type :json
    
    {
      tasks_processed: TaskStats.total_processed,
      active_sessions: SessionManager.active_count,
      uptime: Time.now - start_time
    }.to_json
  end
  
  private
  
  def modify_public_card(card)
    card.metadata ||= {}
    card.metadata[:server_info] = {
      ruby_version: RUBY_VERSION,
      sinatra_version: Sinatra::VERSION,
      uptime: Time.now - start_time
    }
    card
  end
  
  def modify_extended_card(card, context)
    if context.authenticated?
      card.metadata ||= {}
      card.metadata[:user_info] = {
        id: context.user.id,
        name: context.user.name,
        permissions: context.user.permissions
      }
    end
    card
  end
end
```

## Rails Integration

### Engine Mount

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount A2A::Engine => "/a2a"
  
  # Or mount custom A2A app
  mount MyA2AApp => "/custom-a2a"
end
```

### Custom Rails Controller

```ruby
class A2AController < ApplicationController
  before_action :authenticate_user!, only: [:extended_card]
  
  def rpc
    # Create request handler for this request
    handler = create_request_handler
    
    # Parse JSON-RPC request
    rpc_request = A2A::Protocol::JsonRpc.parse_request(request.body.read)
    
    # Route to handler
    result = route_to_handler(rpc_request, handler)
    
    # Return response
    if result.is_a?(Enumerator)
      # Handle streaming
      render_streaming_response(result)
    else
      render json: A2A::Protocol::JsonRpc.build_response(
        result: result,
        id: rpc_request.id
      )
    end
  rescue A2A::Errors::A2AError => e
    render json: A2A::Protocol::JsonRpc.build_error_response(
      code: e.code,
      message: e.message,
      id: rpc_request&.id
    )
  end
  
  def agent_card
    card = build_agent_card
    
    # Apply modifications
    card = modify_card_for_user(card, current_user) if respond_to?(:current_user)
    
    render json: card.to_h
  end
  
  def extended_agent_card
    card = build_extended_agent_card
    card = modify_extended_card_for_user(card, current_user)
    
    render json: card.to_h
  end
  
  private
  
  def create_request_handler
    executor = MyAgentExecutor.new
    A2A::Server::DefaultRequestHandler.new(executor)
  end
  
  def render_streaming_response(enumerator)
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache'
    response.headers['Connection'] = 'keep-alive'
    
    self.response_body = Enumerator.new do |yielder|
      enumerator.each do |event|
        data = event.respond_to?(:to_h) ? event.to_h : event
        yielder << "data: #{data.to_json}\n\n"
      end
    rescue => e
      yielder << "data: #{JSON.generate(error: e.message)}\n\n"
    ensure
      yielder << "data: [DONE]\n\n"
    end
  end
end
```

## Deployment Options

### Puma (Recommended)

```ruby
# config/puma.rb
workers ENV.fetch("WEB_CONCURRENCY") { 2 }
threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
threads threads_count, threads_count

preload_app!

rackup DefaultRackup
port ENV.fetch("PORT") { 3000 }
environment ENV.fetch("RACK_ENV") { "development" }

on_worker_boot do
  # Worker-specific initialization
  A2A.initialize_monitoring!
end
```

### Unicorn

```ruby
# config/unicorn.rb
worker_processes Integer(ENV["WEB_CONCURRENCY"] || 3)
timeout 30
preload_app true

before_fork do |server, worker|
  # Close database connections
  ActiveRecord::Base.connection.disconnect! if defined?(ActiveRecord::Base)
end

after_fork do |server, worker|
  # Reconnect database
  ActiveRecord::Base.establish_connection if defined?(ActiveRecord::Base)
  
  # Initialize A2A monitoring
  A2A.initialize_monitoring!
end
```

### Docker Deployment

```dockerfile
FROM ruby:3.2-alpine

WORKDIR /app

# Install dependencies
COPY Gemfile Gemfile.lock ./
RUN bundle install --deployment --without development test

# Copy application
COPY . .

# Expose port
EXPOSE 9292

# Run with Puma
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
```

```yaml
# docker-compose.yml
version: '3.8'
services:
  a2a-agent:
    build: .
    ports:
      - "9292:9292"
    environment:
      - RACK_ENV=production
      - A2A_LOG_LEVEL=info
    volumes:
      - ./logs:/app/logs
    depends_on:
      - redis
      - postgres
  
  redis:
    image: redis:alpine
    
  postgres:
    image: postgres:13
    environment:
      POSTGRES_DB: a2a_production
      POSTGRES_USER: a2a
      POSTGRES_PASSWORD: secret
```

## Monitoring and Health Checks

### Health Check Endpoint

```ruby
class HealthCheckApp
  def call(env)
    if env['PATH_INFO'] == '/health'
      status = check_health
      
      if status[:healthy]
        [200, {'Content-Type' => 'application/json'}, [status.to_json]]
      else
        [503, {'Content-Type' => 'application/json'}, [status.to_json]]
      end
    else
      [404, {}, ['Not Found']]
    end
  end
  
  private
  
  def check_health
    {
      healthy: true,
      timestamp: Time.now.utc.iso8601,
      version: A2A::VERSION,
      checks: {
        database: check_database,
        redis: check_redis,
        memory: check_memory
      }
    }
  rescue => e
    {
      healthy: false,
      error: e.message,
      timestamp: Time.now.utc.iso8601
    }
  end
end

# Mount health check
map '/health' do
  run HealthCheckApp.new
end

map '/' do
  run a2a_app
end
```

### Metrics Collection

```ruby
class MetricsMiddleware
  def initialize(app)
    @app = app
  end
  
  def call(env)
    start_time = Time.now
    
    status, headers, body = @app.call(env)
    
    duration = Time.now - start_time
    
    # Record metrics
    A2A.record_metric('http_requests_total', 1, 
      method: env['REQUEST_METHOD'],
      path: env['PATH_INFO'],
      status: status
    )
    
    A2A.record_metric('http_request_duration_seconds', duration,
      method: env['REQUEST_METHOD'],
      path: env['PATH_INFO']
    )
    
    [status, headers, body]
  end
end

use MetricsMiddleware
```

## Testing Server Applications

### Testing Rack App

```ruby
RSpec.describe A2A::Server::Apps::RackApp do
  include Rack::Test::Methods
  
  let(:app) { create_test_app }
  
  describe "GET /.well-known/a2a/agent-card" do
    it "returns agent card" do
      get "/.well-known/a2a/agent-card"
      
      expect(last_response).to be_ok
      expect(last_response.content_type).to include('application/json')
      
      card = JSON.parse(last_response.body)
      expect(card['name']).to eq('Test Agent')
    end
  end
  
  describe "POST /a2a/rpc" do
    it "handles JSON-RPC requests" do
      request = {
        jsonrpc: "2.0",
        method: "message/send",
        params: { message: test_message.to_h },
        id: 1
      }
      
      post "/a2a/rpc", request.to_json, 
        'CONTENT_TYPE' => 'application/json'
      
      expect(last_response).to be_ok
      
      response = JSON.parse(last_response.body)
      expect(response['jsonrpc']).to eq('2.0')
      expect(response['id']).to eq(1)
    end
  end
end
```

### Testing Sinatra App

```ruby
RSpec.describe MyA2AApp do
  include Rack::Test::Methods
  
  let(:app) { MyA2AApp }
  
  it "handles authentication" do
    post "/auth/login", {
      username: "test",
      password: "password"
    }
    
    expect(last_response).to be_ok
    
    # Test authenticated request
    get "/admin/stats"
    expect(last_response).to be_ok
  end
end
```

## Best Practices

1. **Security**: Always implement proper authentication and authorization
2. **Error Handling**: Provide meaningful error responses
3. **Logging**: Log important events and errors
4. **Monitoring**: Monitor application health and performance
5. **Testing**: Write comprehensive tests for your endpoints
6. **Documentation**: Document your API endpoints and authentication requirements
7. **Deployment**: Use proper deployment practices with process managers
8. **Scaling**: Consider horizontal scaling for high-traffic scenarios

The server applications provide a solid foundation for deploying A2A agents in production environments while maintaining flexibility for customization and integration with existing systems.

## Complete Examples

For complete working examples of server applications, see the [A2A Ruby Samples Repository](https://github.com/a2aproject/a2a-ruby-samples), which includes:

- **Rack Applications** - Production-ready Rack server examples
- **Sinatra Integration** - Lightweight web service examples  
- **Rails Applications** - Full Rails integration with web UI
- **Docker Deployment** - Container-based deployment examples
- **Multi-Agent Systems** - Complex agent orchestration examples