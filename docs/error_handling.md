# Error Handling and Debugging Guide

This guide covers comprehensive error handling patterns and debugging techniques for the A2A Ruby SDK.

## Table of Contents

- [Error Hierarchy](#error-hierarchy)
- [Error Handling Patterns](#error-handling-patterns)
- [Client-Side Error Handling](#client-side-error-handling)
- [Server-Side Error Handling](#server-side-error-handling)
- [Debugging Techniques](#debugging-techniques)
- [Logging and Monitoring](#logging-and-monitoring)
- [Performance Debugging](#performance-debugging)
- [Common Error Scenarios](#common-error-scenarios)

## Error Hierarchy

The A2A Ruby SDK provides a comprehensive error hierarchy for different types of failures:

```
StandardError
└── A2A::Errors::A2AError
    ├── JSON-RPC Standard Errors
    │   ├── A2A::Errors::ParseError (-32700)
    │   ├── A2A::Errors::InvalidRequest (-32600)
    │   ├── A2A::Errors::MethodNotFound (-32601)
    │   ├── A2A::Errors::InvalidParams (-32602)
    │   └── A2A::Errors::InternalError (-32603)
    ├── A2A Protocol Errors
    │   ├── A2A::Errors::TaskNotFound (-32001)
    │   ├── A2A::Errors::TaskNotCancelable (-32002)
    │   ├── A2A::Errors::InvalidTaskState (-32003)
    │   ├── A2A::Errors::AuthenticationRequired (-32004)
    │   ├── A2A::Errors::InsufficientPermissions (-32005)
    │   ├── A2A::Errors::RateLimitExceeded (-32006)
    │   ├── A2A::Errors::InvalidAgentCard (-32007)
    │   ├── A2A::Errors::TransportNotSupported (-32008)
    │   ├── A2A::Errors::InvalidMessageFormat (-32009)
    │   └── A2A::Errors::ServiceUnavailable (-32010)
    ├── Client Errors
    │   ├── A2A::Errors::ClientError
    │   ├── A2A::Errors::HTTPError
    │   ├── A2A::Errors::TimeoutError
    │   ├── A2A::Errors::AuthenticationError
    │   └── A2A::Errors::ConnectionError
    └── Server Errors
        ├── A2A::Errors::ServerError
        ├── A2A::Errors::ConfigurationError
        └── A2A::Errors::StorageError
```

### Base Error Class

All A2A errors inherit from `A2A::Errors::A2AError`:

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

## Error Handling Patterns

### Comprehensive Error Handling

```ruby
def send_message_with_error_handling(client, message)
  begin
    client.send_message(message) do |response|
      yield response
    end
  rescue A2A::Errors::AuthenticationError => e
    # Handle authentication failures
    logger.warn "Authentication failed: #{e.message}"
    refresh_credentials
    retry
  rescue A2A::Errors::RateLimitExceeded => e
    # Handle rate limiting
    retry_after = e.data&.dig('retry_after') || 60
    logger.info "Rate limited, retrying after #{retry_after}s"
    sleep(retry_after)
    retry
  rescue A2A::Errors::TimeoutError => e
    # Handle timeouts with exponential backoff
    @retry_count ||= 0
    if @retry_count < 3
      @retry_count += 1
      delay = 2 ** @retry_count
      logger.info "Timeout, retrying in #{delay}s (attempt #{@retry_count})"
      sleep(delay)
      retry
    else
      logger.error "Max retries exceeded for timeout"
      raise
    end
  rescue A2A::Errors::TaskNotFound => e
    # Handle missing tasks gracefully
    logger.warn "Task not found: #{e.message}"
    return nil
  rescue A2A::Errors::ServiceUnavailable => e
    # Handle service outages
    logger.error "Service unavailable: #{e.message}"
    notify_service_outage(e)
    raise
  rescue A2A::Errors::A2AError => e
    # Handle all other A2A protocol errors
    logger.error "A2A Protocol Error #{e.code}: #{e.message}"
    handle_protocol_error(e)
  rescue StandardError => e
    # Handle unexpected errors
    logger.error "Unexpected error: #{e.class} - #{e.message}"
    logger.error e.backtrace.join("\n")
    raise
  ensure
    @retry_count = 0
  end
end
```

### Retry with Exponential Backoff

```ruby
class RetryHandler
  def initialize(max_retries: 3, base_delay: 1, max_delay: 60)
    @max_retries = max_retries
    @base_delay = base_delay
    @max_delay = max_delay
  end
  
  def with_retry(&block)
    retries = 0
    
    begin
      yield
    rescue A2A::Errors::TimeoutError, A2A::Errors::HTTPError, A2A::Errors::ServiceUnavailable => e
      retries += 1
      
      if retries <= @max_retries
        delay = [@base_delay * (2 ** (retries - 1)), @max_delay].min
        logger.info "Retrying in #{delay}s (attempt #{retries}/#{@max_retries})"
        sleep(delay)
        retry
      else
        logger.error "Max retries (#{@max_retries}) exceeded"
        raise
      end
    end
  end
end

# Usage
retry_handler = RetryHandler.new(max_retries: 5, base_delay: 2)

retry_handler.with_retry do
  client.send_message(message)
end
```

### Circuit Breaker Pattern

```ruby
class CircuitBreaker
  STATES = [:closed, :open, :half_open].freeze
  
  def initialize(failure_threshold: 5, recovery_timeout: 60)
    @failure_threshold = failure_threshold
    @recovery_timeout = recovery_timeout
    @failure_count = 0
    @last_failure_time = nil
    @state = :closed
  end
  
  def call(&block)
    case @state
    when :open
      if Time.current - @last_failure_time > @recovery_timeout
        @state = :half_open
        logger.info "Circuit breaker transitioning to half-open"
      else
        raise A2A::Errors::ServiceUnavailable, "Circuit breaker is open"
      end
    end
    
    begin
      result = yield
      on_success
      result
    rescue A2A::Errors::A2AError => e
      on_failure
      raise
    end
  end
  
  private
  
  def on_success
    @failure_count = 0
    @state = :closed if @state == :half_open
  end
  
  def on_failure
    @failure_count += 1
    @last_failure_time = Time.current
    
    if @failure_count >= @failure_threshold
      @state = :open
      logger.warn "Circuit breaker opened after #{@failure_count} failures"
    end
  end
end

# Usage
circuit_breaker = CircuitBreaker.new(failure_threshold: 3, recovery_timeout: 30)

circuit_breaker.call do
  client.send_message(message)
end
```

## Client-Side Error Handling

### Connection Errors

```ruby
begin
  client = A2A::Client::HttpClient.new("https://agent.example.com/a2a")
  response = client.send_message(message)
rescue A2A::Errors::ConnectionError => e
  # Network connectivity issues
  logger.error "Connection failed: #{e.message}"
  
  # Check network connectivity
  if network_available?
    # Try alternative endpoint
    fallback_client = A2A::Client::HttpClient.new(fallback_url)
    response = fallback_client.send_message(message)
  else
    # Queue for later processing
    queue_message_for_retry(message)
  end
rescue A2A::Errors::HTTPError => e
  case e.status_code
  when 404
    logger.error "Agent endpoint not found"
  when 500..599
    logger.error "Server error: #{e.status_code}"
    # Implement retry logic
  else
    logger.error "HTTP error: #{e.status_code} - #{e.message}"
  end
end
```

### Authentication Errors

```ruby
class AuthenticatedClient
  def initialize(endpoint_url, auth_strategy)
    @endpoint_url = endpoint_url
    @auth_strategy = auth_strategy
    @client = nil
  end
  
  def send_message(message)
    ensure_authenticated_client
    
    begin
      @client.send_message(message)
    rescue A2A::Errors::AuthenticationError => e
      logger.warn "Authentication failed, refreshing credentials"
      refresh_authentication
      retry
    end
  end
  
  private
  
  def ensure_authenticated_client
    @client ||= A2A::Client::HttpClient.new(@endpoint_url, auth: @auth_strategy)
  end
  
  def refresh_authentication
    case @auth_strategy
    when A2A::Client::Auth::OAuth2
      @auth_strategy.refresh_token!
    when A2A::Client::Auth::JWT
      @auth_strategy.token = fetch_new_jwt_token
    end
    
    # Recreate client with new credentials
    @client = nil
  end
end
```

### Task Management Errors

```ruby
class TaskManager
  def get_task_with_fallback(task_id)
    begin
      client.get_task(task_id)
    rescue A2A::Errors::TaskNotFound => e
      logger.warn "Task #{task_id} not found, checking local cache"
      
      # Try local cache
      cached_task = task_cache.get(task_id)
      return cached_task if cached_task
      
      # Task truly doesn't exist
      raise A2A::Errors::TaskNotFound, "Task #{task_id} not found in remote or cache"
    end
  end
  
  def cancel_task_safely(task_id)
    begin
      task = client.get_task(task_id)
      
      unless task.status.state.in?(['submitted', 'working'])
        logger.info "Task #{task_id} cannot be canceled (state: #{task.status.state})"
        return task
      end
      
      client.cancel_task(task_id)
    rescue A2A::Errors::TaskNotFound => e
      logger.warn "Cannot cancel non-existent task: #{task_id}"
      nil
    rescue A2A::Errors::TaskNotCancelable => e
      logger.warn "Task #{task_id} is not cancelable: #{e.message}"
      client.get_task(task_id)  # Return current state
    end
  end
end
```

## Server-Side Error Handling

### Agent Method Error Handling

```ruby
class WeatherAgent
  include A2A::Server::Agent
  
  a2a_method "get_weather" do |params|
    begin
      validate_weather_params(params)
      
      location = params[:location]
      weather_data = fetch_weather_data(location)
      
      format_weather_response(weather_data)
    rescue ValidationError => e
      # Return A2A error for invalid parameters
      raise A2A::Errors::InvalidParams, "Invalid location: #{e.message}"
    rescue WeatherServiceError => e
      # Handle external service errors
      logger.error "Weather service error: #{e.message}"
      raise A2A::Errors::ServiceUnavailable, "Weather service temporarily unavailable"
    rescue => e
      # Handle unexpected errors
      logger.error "Unexpected error in get_weather: #{e.class} - #{e.message}"
      logger.error e.backtrace.join("\n")
      raise A2A::Errors::InternalError, "Internal server error"
    end
  end
  
  a2a_method "weather_forecast", streaming: true do |params|
    Enumerator.new do |yielder|
      begin
        validate_forecast_params(params)
        
        # Initial status
        yielder << task_status_update("working", "Fetching forecast data")
        
        forecast_data = fetch_forecast_data(params[:location], params[:days])
        
        forecast_data.each_with_index do |day_data, index|
          begin
            formatted_day = format_day_forecast(day_data)
            
            message = A2A::Types::Message.new(
              message_id: SecureRandom.uuid,
              role: "agent",
              parts: [A2A::Types::TextPart.new(text: formatted_day.to_json)]
            )
            yielder << message
            
            # Progress update
            progress = ((index + 1).to_f / forecast_data.size * 100).round
            yielder << task_status_update("working", "Progress: #{progress}%", progress)
          rescue => e
            logger.error "Error processing day #{index}: #{e.message}"
            # Continue with other days, don't fail entire forecast
          end
        end
        
        # Completion
        yielder << task_status_update("completed", "Forecast complete")
      rescue ValidationError => e
        yielder << task_status_update("failed", "Invalid parameters: #{e.message}")
      rescue ForecastServiceError => e
        yielder << task_status_update("failed", "Forecast service unavailable")
      rescue => e
        logger.error "Unexpected error in weather_forecast: #{e.message}"
        yielder << task_status_update("failed", "Internal server error")
      end
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
        progress: progress,
        updated_at: Time.current.iso8601
      )
    )
  end
end
```

### Middleware Error Handling

```ruby
class ErrorHandlingMiddleware
  def initialize(app)
    @app = app
  end
  
  def call(request)
    begin
      @app.call(request)
    rescue A2A::Errors::A2AError => e
      # A2A protocol errors - return proper JSON-RPC error
      {
        jsonrpc: "2.0",
        error: e.to_json_rpc_error,
        id: request.id
      }
    rescue ValidationError => e
      # Convert validation errors to A2A format
      {
        jsonrpc: "2.0",
        error: {
          code: -32602,
          message: "Invalid params",
          data: { validation_errors: e.errors }
        },
        id: request.id
      }
    rescue => e
      # Log unexpected errors and return generic error
      logger.error "Unexpected error: #{e.class} - #{e.message}"
      logger.error e.backtrace.join("\n")
      
      {
        jsonrpc: "2.0",
        error: {
          code: -32603,
          message: "Internal error"
        },
        id: request.id
      }
    end
  end
end
```

### Rails Error Handling

```ruby
class WeatherAgentController < ApplicationController
  include A2A::Rails::ControllerHelpers
  
  rescue_from A2A::Errors::A2AError, with: :handle_a2a_error
  rescue_from ActiveRecord::RecordNotFound, with: :handle_not_found
  rescue_from StandardError, with: :handle_unexpected_error
  
  private
  
  def handle_a2a_error(error)
    logger.warn "A2A Error #{error.code}: #{error.message}"
    
    render json: {
      jsonrpc: "2.0",
      error: error.to_json_rpc_error,
      id: params[:id]
    }, status: :bad_request
  end
  
  def handle_not_found(error)
    logger.warn "Resource not found: #{error.message}"
    
    render json: {
      jsonrpc: "2.0",
      error: {
        code: -32001,
        message: "Resource not found"
      },
      id: params[:id]
    }, status: :not_found
  end
  
  def handle_unexpected_error(error)
    logger.error "Unexpected error: #{error.class} - #{error.message}"
    logger.error error.backtrace.join("\n")
    
    # Report to error tracking service
    Bugsnag.notify(error) if defined?(Bugsnag)
    
    render json: {
      jsonrpc: "2.0",
      error: {
        code: -32603,
        message: "Internal server error"
      },
      id: params[:id]
    }, status: :internal_server_error
  end
end
```

## Debugging Techniques

### Enable Debug Logging

```ruby
# Enable comprehensive debug logging
A2A.configure do |config|
  config.log_level = :debug
  config.log_requests = true
  config.log_responses = true
  config.log_request_bodies = true
  config.log_response_bodies = true
end
```

### Request/Response Inspection

```ruby
class DebuggingMiddleware
  def initialize(app)
    @app = app
  end
  
  def call(env)
    request_id = SecureRandom.uuid
    
    logger.debug "Request #{request_id}: #{env['REQUEST_METHOD']} #{env['PATH_INFO']}"
    logger.debug "Headers: #{env.select { |k, v| k.start_with?('HTTP_') }}"
    
    if env['rack.input']
      body = env['rack.input'].read
      env['rack.input'].rewind
      logger.debug "Body: #{body}"
    end
    
    start_time = Time.current
    response = @app.call(env)
    duration = Time.current - start_time
    
    logger.debug "Response #{request_id}: #{response[0]} (#{duration}s)"
    logger.debug "Response Headers: #{response[1]}"
    
    response
  end
end
```

### Client Debugging

```ruby
# Add debugging to client
client = A2A::Client::HttpClient.new(url) do |conn|
  # Log all HTTP requests/responses
  conn.response :logger, Rails.logger, bodies: true
  
  # Add custom debugging middleware
  conn.use DebuggingMiddleware
end

# Enable request tracing
client.add_middleware(A2A::Client::Middleware::TracingInterceptor.new)
```

### Task Debugging

```ruby
class TaskDebugger
  def self.debug_task(task_id, client: nil)
    client ||= A2A::Client::HttpClient.new(ENV['A2A_ENDPOINT'])
    
    begin
      task = client.get_task(task_id)
      
      puts "Task ID: #{task.id}"
      puts "Context ID: #{task.context_id}"
      puts "Status: #{task.status.state}"
      puts "Progress: #{task.status.progress}%" if task.status.progress
      puts "Message: #{task.status.message}" if task.status.message
      puts "Updated: #{task.status.updated_at}"
      
      if task.status.error
        puts "Error: #{task.status.error}"
      end
      
      if task.artifacts&.any?
        puts "Artifacts:"
        task.artifacts.each do |artifact|
          puts "  - #{artifact.name}: #{artifact.parts.size} parts"
        end
      end
      
      if task.history&.any?
        puts "Message History (#{task.history.size} messages):"
        task.history.last(5).each do |message|
          puts "  #{message.role}: #{message.parts.first&.text&.truncate(100)}"
        end
      end
    rescue A2A::Errors::TaskNotFound
      puts "Task #{task_id} not found"
    rescue => e
      puts "Error debugging task: #{e.message}"
    end
  end
end

# Usage
TaskDebugger.debug_task("task-123")
```

## Logging and Monitoring

### Structured Logging

```ruby
A2A.configure do |config|
  config.structured_logging = true
  config.log_format = :json
  config.log_correlation_id = true
end

# Custom structured logger
class A2ALogger
  def self.log_request(request, response: nil, duration: nil, error: nil)
    log_data = {
      timestamp: Time.current.iso8601,
      type: 'a2a_request',
      method: request.method,
      params: request.params,
      request_id: request.id,
      correlation_id: Thread.current[:correlation_id]
    }
    
    if response
      log_data[:response] = {
        success: !response.key?('error'),
        result_size: response['result']&.to_s&.size
      }
    end
    
    if duration
      log_data[:duration_ms] = (duration * 1000).round(2)
    end
    
    if error
      log_data[:error] = {
        class: error.class.name,
        message: error.message,
        code: error.respond_to?(:code) ? error.code : nil
      }
    end
    
    Rails.logger.info(log_data.to_json)
  end
end
```

### Metrics Collection

```ruby
class A2AMetrics
  def self.record_request(method:, success:, duration:, error_code: nil)
    # Prometheus metrics
    if defined?(Prometheus)
      A2A_REQUEST_COUNTER.increment(
        labels: { method: method, success: success }
      )
      
      A2A_REQUEST_DURATION.observe(
        duration,
        labels: { method: method }
      )
      
      if error_code
        A2A_ERROR_COUNTER.increment(
          labels: { method: method, error_code: error_code }
        )
      end
    end
    
    # StatsD metrics
    if defined?(Statsd)
      Statsd.increment('a2a.requests', tags: ["method:#{method}", "success:#{success}"])
      Statsd.histogram('a2a.request_duration', duration, tags: ["method:#{method}"])
      
      if error_code
        Statsd.increment('a2a.errors', tags: ["method:#{method}", "code:#{error_code}"])
      end
    end
  end
end
```

### Health Checks

```ruby
class A2AHealthCheck
  def self.check_agent_health(endpoint_url)
    begin
      client = A2A::Client::HttpClient.new(endpoint_url)
      
      # Check agent card retrieval
      start_time = Time.current
      card = client.get_card
      card_duration = Time.current - start_time
      
      # Check basic message sending
      start_time = Time.current
      test_message = A2A::Types::Message.new(
        message_id: SecureRandom.uuid,
        role: "user",
        parts: [A2A::Types::TextPart.new(text: "health_check")]
      )
      
      response = client.send_message(test_message, streaming: false)
      message_duration = Time.current - start_time
      
      {
        status: 'healthy',
        agent_name: card.name,
        agent_version: card.version,
        response_times: {
          agent_card: card_duration,
          message_send: message_duration
        },
        timestamp: Time.current.iso8601
      }
    rescue => e
      {
        status: 'unhealthy',
        error: e.message,
        error_class: e.class.name,
        timestamp: Time.current.iso8601
      }
    end
  end
end
```

## Performance Debugging

### Memory Profiling

```ruby
require 'memory_profiler'

# Profile memory usage
report = MemoryProfiler.report do
  client.send_message(message) do |response|
    process_response(response)
  end
end

puts report.pretty_print
```

### CPU Profiling

```ruby
require 'ruby-prof'

# Profile CPU usage
RubyProf.start

client.send_message(message) do |response|
  process_response(response)
end

result = RubyProf.stop

# Print flat profile
printer = RubyProf::FlatPrinter.new(result)
printer.print(STDOUT)
```

### Connection Pool Monitoring

```ruby
class ConnectionPoolMonitor
  def self.monitor_pool(pool)
    {
      size: pool.size,
      available: pool.available,
      checked_out: pool.size - pool.available,
      utilization: ((pool.size - pool.available).to_f / pool.size * 100).round(2)
    }
  end
end

# Monitor HTTP connection pool
pool_stats = ConnectionPoolMonitor.monitor_pool(Faraday.default_connection.pool)
logger.info "Connection pool stats: #{pool_stats}"
```

## Common Error Scenarios

### Scenario 1: Agent Unavailable

```ruby
def handle_agent_unavailable(primary_client, fallback_clients = [])
  begin
    primary_client.send_message(message)
  rescue A2A::Errors::ServiceUnavailable, A2A::Errors::TimeoutError => e
    logger.warn "Primary agent unavailable: #{e.message}"
    
    fallback_clients.each_with_index do |fallback_client, index|
      begin
        logger.info "Trying fallback agent #{index + 1}"
        return fallback_client.send_message(message)
      rescue A2A::Errors::ServiceUnavailable, A2A::Errors::TimeoutError => e
        logger.warn "Fallback agent #{index + 1} also unavailable: #{e.message}"
        next
      end
    end
    
    # All agents unavailable
    raise A2A::Errors::ServiceUnavailable, "All agents unavailable"
  end
end
```

### Scenario 2: Authentication Token Expiry

```ruby
class TokenManager
  def initialize(auth_strategy)
    @auth_strategy = auth_strategy
    @token_expires_at = nil
  end
  
  def ensure_valid_token
    if token_expired?
      refresh_token
    end
  end
  
  private
  
  def token_expired?
    @token_expires_at && Time.current >= @token_expires_at - 60 # 1 minute buffer
  end
  
  def refresh_token
    case @auth_strategy
    when A2A::Client::Auth::OAuth2
      token, expires_in = @auth_strategy.get_token
      @token_expires_at = Time.current + expires_in
    when A2A::Client::Auth::JWT
      @auth_strategy.token = fetch_new_jwt_token
      payload = JWT.decode(@auth_strategy.token, nil, false)
      @token_expires_at = Time.at(payload[0]['exp'])
    end
  end
end
```

### Scenario 3: Large Message Handling

```ruby
def send_large_message_safely(client, message)
  # Check message size
  message_size = message.to_json.bytesize
  
  if message_size > 10.megabytes
    logger.warn "Large message detected: #{message_size} bytes"
    
    # Split into smaller chunks or use file references
    return send_chunked_message(client, message)
  end
  
  # Increase timeout for large messages
  original_timeout = client.config.timeout
  client.config.timeout = [original_timeout * 2, 300].min
  
  begin
    client.send_message(message)
  ensure
    client.config.timeout = original_timeout
  end
end
```

For more debugging help, see the [Troubleshooting Guide](troubleshooting.md) and [API Reference](api_reference.md).