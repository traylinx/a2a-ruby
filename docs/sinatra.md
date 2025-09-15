# Sinatra Integration Guide

This guide covers integrating the A2A Ruby SDK with Sinatra applications for lightweight A2A agent development.

## Table of Contents

- [Basic Setup](#basic-setup)
- [Simple A2A Agent](#simple-a2a-agent)
- [Advanced Agent Features](#advanced-agent-features)
- [Authentication](#authentication)
- [Error Handling](#error-handling)
- [Testing](#testing)
- [Deployment](#deployment)
- [Performance Optimization](#performance-optimization)

## Basic Setup

### Installation

```ruby
# Gemfile
source 'https://rubygems.org'

gem 'sinatra'
gem 'a2a-ruby'
gem 'json'
gem 'puma'  # Web server

# Optional dependencies
gem 'redis'           # For caching and storage
gem 'sidekiq'         # For background jobs
gem 'rack-cors'       # For CORS support
gem 'rack-protection' # Security middleware

group :development do
  gem 'rerun'  # Auto-restart during development
end

group :test do
  gem 'rspec'
  gem 'rack-test'
end
```

### Basic Application Structure

```
weather_agent/
├── Gemfile
├── config.ru
├── app.rb
├── lib/
│   ├── weather_service.rb
│   └── agents/
│       └── weather_agent.rb
├── config/
│   └── a2a.rb
└── spec/
    └── app_spec.rb
```

### Configuration

```ruby
# config/a2a.rb
require 'a2a'

A2A.configure do |config|
  config.protocol_version = "0.3.0"
  config.default_transport = "JSONRPC"
  config.streaming_enabled = true
  config.log_level = ENV['A2A_LOG_LEVEL']&.to_sym || :info
  config.storage_backend = ENV['A2A_STORAGE_BACKEND']&.to_sym || :memory
  
  # Redis configuration (if using Redis storage)
  if config.storage_backend == :redis
    config.redis_url = ENV['REDIS_URL'] || 'redis://localhost:6379/0'
  end
end
```

### Basic Sinatra Application

```ruby
# app.rb
require 'sinatra'
require 'json'
require_relative 'config/a2a'
require_relative 'lib/agents/weather_agent'

# Enable CORS for A2A requests
before do
  if request.path.start_with?('/a2a')
    headers 'Access-Control-Allow-Origin' => '*'
    headers 'Access-Control-Allow-Methods' => 'GET, POST, OPTIONS'
    headers 'Access-Control-Allow-Headers' => 'Content-Type, Authorization'
  end
end

# Handle preflight requests
options '*' do
  200
end

# A2A JSON-RPC endpoint
post '/a2a/rpc' do
  content_type :json
  
  begin
    request_body = request.body.read
    json_rpc_request = A2A::Protocol::JsonRpc.parse_request(request_body)
    
    agent = WeatherAgent.new
    response = agent.handle_a2a_request(json_rpc_request)
    
    response.to_json
  rescue A2A::Errors::A2AError => e
    status 400
    e.to_json_rpc_error.to_json
  rescue JSON::ParserError => e
    status 400
    {
      jsonrpc: "2.0",
      error: {
        code: -32700,
        message: "Parse error"
      },
      id: nil
    }.to_json
  rescue => e
    logger.error "Unexpected error: #{e.message}"
    status 500
    {
      jsonrpc: "2.0",
      error: {
        code: -32603,
        message: "Internal error"
      },
      id: nil
    }.to_json
  end
end

# Agent card endpoint
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

# Health check endpoint
get '/a2a/health' do
  content_type :json
  
  {
    status: 'healthy',
    timestamp: Time.now.iso8601,
    version: '1.0.0'
  }.to_json
end

# Root endpoint
get '/' do
  content_type :json
  
  {
    name: "Weather Agent",
    description: "A2A Weather Service",
    endpoints: {
      rpc: "#{request.base_url}/a2a/rpc",
      agent_card: "#{request.base_url}/a2a/agent-card",
      health: "#{request.base_url}/a2a/health"
    }
  }.to_json
end
```

### Rack Configuration

```ruby
# config.ru
require_relative 'app'

# Security middleware
use Rack::Protection

# Logging
use Rack::CommonLogger

run Sinatra::Application
```

## Simple A2A Agent

### Weather Service

```ruby
# lib/weather_service.rb
class WeatherService
  class LocationNotFound < StandardError; end
  class ServiceError < StandardError; end
  
  def self.current(location)
    # Simulate API call
    sleep(0.1)  # Simulate network delay
    
    case location.downcase
    when 'error'
      raise ServiceError, "Weather service unavailable"
    when 'notfound'
      raise LocationNotFound, "Location not found"
    else
      OpenStruct.new(
        temperature: "#{rand(60..85)}°F",
        condition: %w[Sunny Cloudy Rainy Snowy].sample,
        humidity: "#{rand(30..80)}%",
        wind_speed: "#{rand(0..15)} mph",
        timestamp: Time.now.iso8601
      )
    end
  end
  
  def self.forecast(location, days = 5)
    # Simulate forecast data
    (0...days).map do |day_offset|
      date = Date.today + day_offset
      OpenStruct.new(
        date: date,
        high_temp: rand(70..85),
        low_temp: rand(50..65),
        condition: %w[Sunny Cloudy Rainy].sample,
        precipitation_chance: rand(0..100)
      )
    end
  end
end
```

### Weather Agent

```ruby
# lib/agents/weather_agent.rb
require 'a2a'
require_relative '../weather_service'

class WeatherAgent
  include A2A::Server::Agent
  
  # Agent configuration
  a2a_config(
    name: "Weather Agent",
    description: "Provides current weather and forecast information",
    version: "1.0.0"
  )
  
  # Define skills
  a2a_skill "current_weather" do |skill|
    skill.description = "Get current weather conditions"
    skill.tags = ["weather", "current", "conditions"]
    skill.examples = [
      "What's the weather in New York?",
      "Current conditions in San Francisco"
    ]
    skill.input_modes = ["text"]
    skill.output_modes = ["text", "structured"]
  end
  
  a2a_skill "weather_forecast" do |skill|
    skill.description = "Get weather forecast for multiple days"
    skill.tags = ["weather", "forecast", "prediction"]
    skill.examples = [
      "5-day forecast for London",
      "Weather forecast for next week"
    ]
    skill.input_modes = ["text"]
    skill.output_modes = ["text", "structured"]
  end
  
  # A2A method implementations
  a2a_method "get_current_weather" do |params|
    location = params[:location]
    
    raise A2A::Errors::InvalidParams, "Location is required" if location.nil? || location.empty?
    
    begin
      weather_data = WeatherService.current(location)
      
      {
        location: location,
        temperature: weather_data.temperature,
        condition: weather_data.condition,
        humidity: weather_data.humidity,
        wind_speed: weather_data.wind_speed,
        timestamp: weather_data.timestamp
      }
    rescue WeatherService::LocationNotFound => e
      raise A2A::Errors::InvalidParams, "Location '#{location}' not found"
    rescue WeatherService::ServiceError => e
      raise A2A::Errors::ServiceUnavailable, "Weather service temporarily unavailable"
    end
  end
  
  a2a_method "get_weather_forecast", streaming: true do |params|
    location = params[:location]
    days = params[:days] || 5
    
    # Validation
    raise A2A::Errors::InvalidParams, "Location is required" if location.nil? || location.empty?
    raise A2A::Errors::InvalidParams, "Days must be between 1 and 10" unless (1..10).include?(days)
    
    Enumerator.new do |yielder|
      begin
        # Initial status
        yielder << task_status_update(params, "working", "Fetching #{days}-day forecast for #{location}")
        
        # Get forecast data
        forecast_data = WeatherService.forecast(location, days)
        
        # Stream each day's forecast
        forecast_data.each_with_index do |day_forecast, index|
          # Create message for this day
          day_message = {
            date: day_forecast.date.iso8601,
            high_temperature: "#{day_forecast.high_temp}°F",
            low_temperature: "#{day_forecast.low_temp}°F",
            condition: day_forecast.condition,
            precipitation_chance: "#{day_forecast.precipitation_chance}%"
          }
          
          message = A2A::Types::Message.new(
            message_id: SecureRandom.uuid,
            role: "agent",
            parts: [
              A2A::Types::TextPart.new(
                text: "Day #{index + 1}: #{day_forecast.condition}, High: #{day_forecast.high_temp}°F, Low: #{day_forecast.low_temp}°F"
              ),
              A2A::Types::DataPart.new(data: day_message)
            ]
          )
          yielder << message
          
          # Progress update
          progress = ((index + 1).to_f / days * 100).round
          yielder << task_status_update(params, "working", "Progress: #{progress}%", progress)
        end
        
        # Final completion
        yielder << task_status_update(params, "completed", "#{days}-day forecast complete")
      rescue WeatherService::LocationNotFound => e
        yielder << task_status_update(params, "failed", "Location '#{location}' not found")
      rescue WeatherService::ServiceError => e
        yielder << task_status_update(params, "failed", "Weather service error: #{e.message}")
      rescue => e
        puts "Unexpected error in forecast: #{e.message}"
        yielder << task_status_update(params, "failed", "Internal server error")
      end
    end
  end
  
  private
  
  def task_status_update(params, state, message = nil, progress = nil)
    A2A::Types::TaskStatusUpdateEvent.new(
      task_id: params[:task_id] || SecureRandom.uuid,
      context_id: params[:context_id] || SecureRandom.uuid,
      status: A2A::Types::TaskStatus.new(
        state: state,
        message: message,
        progress: progress,
        updated_at: Time.now.iso8601
      )
    )
  end
end
```

## Advanced Agent Features

### Multi-Agent Application

```ruby
# app.rb - Extended version with multiple agents
require 'sinatra'
require 'json'
require_relative 'config/a2a'
require_relative 'lib/agents/weather_agent'
require_relative 'lib/agents/calculator_agent'
require_relative 'lib/agents/echo_agent'

# Agent registry
AGENTS = {
  'weather' => WeatherAgent,
  'calculator' => CalculatorAgent,
  'echo' => EchoAgent
}.freeze

# Dynamic agent routing
AGENTS.each do |agent_name, agent_class|
  # RPC endpoint for each agent
  post "/a2a/#{agent_name}/rpc" do
    content_type :json
    handle_agent_request(agent_class)
  end
  
  # Agent card for each agent
  get "/a2a/#{agent_name}/agent-card" do
    content_type :json
    
    agent = agent_class.new
    card = agent.generate_agent_card(
      url: "#{request.base_url}/a2a/#{agent_name}"
    )
    
    card.to_h.to_json
  end
end

# List all agents
get '/a2a/agents' do
  content_type :json
  
  agents_info = AGENTS.map do |name, agent_class|
    agent = agent_class.new
    {
      name: name,
      display_name: agent.class.name,
      endpoints: {
        rpc: "#{request.base_url}/a2a/#{name}/rpc",
        agent_card: "#{request.base_url}/a2a/#{name}/agent-card"
      }
    }
  end
  
  {
    agents: agents_info,
    total: agents_info.size
  }.to_json
end

# Generic agent request handler
def handle_agent_request(agent_class)
  begin
    request_body = request.body.read
    json_rpc_request = A2A::Protocol::JsonRpc.parse_request(request_body)
    
    agent = agent_class.new
    response = agent.handle_a2a_request(json_rpc_request)
    
    response.to_json
  rescue A2A::Errors::A2AError => e
    status 400
    e.to_json_rpc_error.to_json
  rescue => e
    logger.error "Agent request error: #{e.message}"
    status 500
    {
      jsonrpc: "2.0",
      error: { code: -32603, message: "Internal error" },
      id: nil
    }.to_json
  end
end
```

### Calculator Agent

```ruby
# lib/agents/calculator_agent.rb
class CalculatorAgent
  include A2A::Server::Agent
  
  a2a_config(
    name: "Calculator Agent",
    description: "Performs mathematical calculations",
    version: "1.0.0"
  )
  
  a2a_skill "arithmetic" do |skill|
    skill.description = "Basic arithmetic operations"
    skill.tags = ["math", "calculation", "arithmetic"]
    skill.examples = ["2 + 2", "10 * 5", "100 / 4"]
  end
  
  a2a_skill "advanced_math" do |skill|
    skill.description = "Advanced mathematical functions"
    skill.tags = ["math", "advanced", "functions"]
    skill.examples = ["sqrt(16)", "sin(30)", "log(100)"]
  end
  
  a2a_method "calculate" do |params|
    expression = params[:expression]
    
    raise A2A::Errors::InvalidParams, "Expression is required" if expression.nil? || expression.empty?
    
    begin
      # Simple expression evaluation (be careful with eval in production!)
      result = safe_eval(expression)
      
      {
        expression: expression,
        result: result,
        timestamp: Time.now.iso8601
      }
    rescue => e
      raise A2A::Errors::InvalidParams, "Invalid expression: #{e.message}"
    end
  end
  
  a2a_method "batch_calculate", streaming: true do |params|
    expressions = params[:expressions]
    
    raise A2A::Errors::InvalidParams, "Expressions array is required" unless expressions.is_a?(Array)
    
    Enumerator.new do |yielder|
      yielder << task_status_update(params, "working", "Processing #{expressions.size} expressions")
      
      expressions.each_with_index do |expression, index|
        begin
          result = safe_eval(expression)
          
          message = A2A::Types::Message.new(
            message_id: SecureRandom.uuid,
            role: "agent",
            parts: [
              A2A::Types::DataPart.new(data: {
                expression: expression,
                result: result,
                index: index
              })
            ]
          )
          yielder << message
          
          progress = ((index + 1).to_f / expressions.size * 100).round
          yielder << task_status_update(params, "working", "Processed #{index + 1}/#{expressions.size}", progress)
        rescue => e
          error_message = A2A::Types::Message.new(
            message_id: SecureRandom.uuid,
            role: "agent",
            parts: [
              A2A::Types::DataPart.new(data: {
                expression: expression,
                error: e.message,
                index: index
              })
            ]
          )
          yielder << error_message
        end
      end
      
      yielder << task_status_update(params, "completed", "All expressions processed")
    end
  end
  
  private
  
  def safe_eval(expression)
    # Whitelist allowed operations for security
    allowed_chars = /\A[0-9+\-*\/\.\(\)\s]+\z/
    
    raise "Invalid characters in expression" unless expression.match?(allowed_chars)
    
    # Use a safer evaluation method in production
    eval(expression)
  end
  
  def task_status_update(params, state, message = nil, progress = nil)
    A2A::Types::TaskStatusUpdateEvent.new(
      task_id: params[:task_id] || SecureRandom.uuid,
      context_id: params[:context_id] || SecureRandom.uuid,
      status: A2A::Types::TaskStatus.new(
        state: state,
        message: message,
        progress: progress,
        updated_at: Time.now.iso8601
      )
    )
  end
end
```

### File Processing Agent

```ruby
# lib/agents/file_processor_agent.rb
class FileProcessorAgent
  include A2A::Server::Agent
  
  a2a_config(
    name: "File Processor",
    description: "Processes and analyzes uploaded files",
    version: "1.0.0"
  )
  
  a2a_skill "file_analysis" do |skill|
    skill.description = "Analyze file content and metadata"
    skill.tags = ["file", "analysis", "processing"]
    skill.input_modes = ["file", "text"]
    skill.output_modes = ["structured", "text"]
  end
  
  a2a_method "analyze_file" do |params|
    # Extract file from message parts
    message = params[:message]
    file_part = extract_file_part(message)
    
    raise A2A::Errors::InvalidParams, "File is required" unless file_part
    
    file_info = file_part[:file]
    file_name = file_info[:name]
    mime_type = file_info[:mime_type]
    
    # Decode file content
    file_content = if file_info[:bytes]
      Base64.decode64(file_info[:bytes])
    elsif file_info[:uri]
      # In production, you'd fetch from the URI
      "Content from #{file_info[:uri]}"
    else
      raise A2A::Errors::InvalidParams, "File must have bytes or uri"
    end
    
    # Analyze file
    analysis = analyze_file_content(file_content, mime_type)
    
    {
      file_name: file_name,
      mime_type: mime_type,
      size_bytes: file_content.bytesize,
      analysis: analysis,
      timestamp: Time.now.iso8601
    }
  end
  
  private
  
  def extract_file_part(message)
    return nil unless message && message[:parts]
    
    message[:parts].find { |part| part[:kind] == 'file' }
  end
  
  def analyze_file_content(content, mime_type)
    case mime_type
    when 'text/plain'
      {
        type: 'text',
        line_count: content.lines.count,
        word_count: content.split.size,
        character_count: content.size
      }
    when 'application/json'
      begin
        data = JSON.parse(content)
        {
          type: 'json',
          valid: true,
          keys: data.is_a?(Hash) ? data.keys : nil,
          size: data.size
        }
      rescue JSON::ParserError
        { type: 'json', valid: false, error: 'Invalid JSON' }
      end
    else
      {
        type: 'binary',
        size_bytes: content.bytesize,
        encoding: content.encoding.name
      }
    end
  end
end
```

## Authentication

### JWT Authentication

```ruby
# lib/middleware/jwt_auth.rb
require 'jwt'

class JWTAuth
  def initialize(app, secret_key)
    @app = app
    @secret_key = secret_key
  end
  
  def call(env)
    request = Rack::Request.new(env)
    
    # Only authenticate A2A requests
    if request.path.start_with?('/a2a/') && request.post?
      token = extract_token(request)
      
      if token
        begin
          payload = JWT.decode(token, @secret_key, true, algorithm: 'HS256')
          env['a2a.user'] = payload[0]
        rescue JWT::DecodeError => e
          return [401, {}, [{ error: 'Invalid token' }.to_json]]
        end
      else
        return [401, {}, [{ error: 'Authentication required' }.to_json]]
      end
    end
    
    @app.call(env)
  end
  
  private
  
  def extract_token(request)
    auth_header = request.get_header('HTTP_AUTHORIZATION')
    return nil unless auth_header
    
    auth_header.sub(/^Bearer /, '')
  end
end

# app.rb - Add authentication middleware
use JWTAuth, ENV['JWT_SECRET'] || 'your-secret-key'

# Access authenticated user in agents
class SecureAgent
  include A2A::Server::Agent
  
  a2a_method "secure_operation" do |params|
    # Access user from Rack environment
    user = env['a2a.user']
    
    {
      message: "Hello, #{user['name']}!",
      user_id: user['user_id'],
      timestamp: Time.now.iso8601
    }
  end
end
```

### API Key Authentication

```ruby
# lib/middleware/api_key_auth.rb
class ApiKeyAuth
  def initialize(app)
    @app = app
    @valid_keys = ENV['API_KEYS']&.split(',') || []
  end
  
  def call(env)
    request = Rack::Request.new(env)
    
    if request.path.start_with?('/a2a/') && request.post?
      api_key = request.get_header('HTTP_X_API_KEY')
      
      unless @valid_keys.include?(api_key)
        return [401, {}, [{ error: 'Invalid API key' }.to_json]]
      end
      
      env['a2a.api_key'] = api_key
    end
    
    @app.call(env)
  end
end

# app.rb
use ApiKeyAuth
```

## Error Handling

### Comprehensive Error Handling

```ruby
# lib/middleware/error_handler.rb
class ErrorHandler
  def initialize(app)
    @app = app
  end
  
  def call(env)
    begin
      @app.call(env)
    rescue A2A::Errors::A2AError => e
      [400, { 'Content-Type' => 'application/json' }, [e.to_json_rpc_error.to_json]]
    rescue JSON::ParserError => e
      error_response = {
        jsonrpc: "2.0",
        error: { code: -32700, message: "Parse error" },
        id: nil
      }
      [400, { 'Content-Type' => 'application/json' }, [error_response.to_json]]
    rescue => e
      puts "Unexpected error: #{e.message}"
      puts e.backtrace
      
      error_response = {
        jsonrpc: "2.0",
        error: { code: -32603, message: "Internal error" },
        id: nil
      }
      [500, { 'Content-Type' => 'application/json' }, [error_response.to_json]]
    end
  end
end

# app.rb
use ErrorHandler
```

### Custom Error Pages

```ruby
# app.rb
error 404 do
  content_type :json
  {
    error: "Not Found",
    message: "The requested endpoint does not exist",
    available_endpoints: [
      "/a2a/rpc",
      "/a2a/agent-card",
      "/a2a/health"
    ]
  }.to_json
end

error 500 do
  content_type :json
  {
    error: "Internal Server Error",
    message: "An unexpected error occurred"
  }.to_json
end
```

## Testing

### RSpec Configuration

```ruby
# spec/spec_helper.rb
require 'rack/test'
require 'rspec'
require 'json'
require_relative '../app'

RSpec.configure do |config|
  config.include Rack::Test::Methods
  
  def app
    Sinatra::Application
  end
end
```

### Agent Testing

```ruby
# spec/agents/weather_agent_spec.rb
require 'spec_helper'
require_relative '../../lib/agents/weather_agent'

RSpec.describe WeatherAgent do
  let(:agent) { WeatherAgent.new }
  
  describe "#get_current_weather" do
    it "returns weather data for valid location" do
      allow(WeatherService).to receive(:current).with("New York").and_return(
        OpenStruct.new(
          temperature: "72°F",
          condition: "Sunny",
          humidity: "45%",
          wind_speed: "5 mph",
          timestamp: Time.now.iso8601
        )
      )
      
      result = agent.get_current_weather({ location: "New York" })
      
      expect(result[:location]).to eq("New York")
      expect(result[:temperature]).to eq("72°F")
      expect(result[:condition]).to eq("Sunny")
    end
    
    it "raises error for missing location" do
      expect {
        agent.get_current_weather({})
      }.to raise_error(A2A::Errors::InvalidParams, "Location is required")
    end
    
    it "handles service errors" do
      allow(WeatherService).to receive(:current).and_raise(WeatherService::ServiceError)
      
      expect {
        agent.get_current_weather({ location: "New York" })
      }.to raise_error(A2A::Errors::ServiceUnavailable)
    end
  end
  
  describe "#get_weather_forecast" do
    it "streams forecast data" do
      forecast_data = [
        OpenStruct.new(date: Date.today, high_temp: 75, low_temp: 60, condition: "Sunny"),
        OpenStruct.new(date: Date.today + 1, high_temp: 73, low_temp: 58, condition: "Cloudy")
      ]
      allow(WeatherService).to receive(:forecast).and_return(forecast_data)
      
      responses = []
      agent.get_weather_forecast({
        location: "San Francisco",
        days: 2,
        task_id: "test-task",
        context_id: "test-context"
      }).each do |response|
        responses << response
      end
      
      # Should have status updates and messages
      expect(responses).to include(
        an_instance_of(A2A::Types::TaskStatusUpdateEvent),
        an_instance_of(A2A::Types::Message)
      )
      
      # Check final status
      final_status = responses.select { |r| r.is_a?(A2A::Types::TaskStatusUpdateEvent) }.last
      expect(final_status.status.state).to eq("completed")
    end
  end
end
```

### Integration Testing

```ruby
# spec/app_spec.rb
require 'spec_helper'

RSpec.describe "Weather Agent API" do
  describe "GET /a2a/agent-card" do
    it "returns agent card" do
      get '/a2a/agent-card'
      
      expect(last_response).to be_ok
      
      card = JSON.parse(last_response.body)
      expect(card['name']).to eq("Weather Agent")
      expect(card['skills']).to be_an(Array)
    end
  end
  
  describe "POST /a2a/rpc" do
    it "handles weather requests" do
      allow(WeatherService).to receive(:current).and_return(
        OpenStruct.new(temperature: "70°F", condition: "Sunny")
      )
      
      request_body = {
        jsonrpc: "2.0",
        method: "get_current_weather",
        params: { location: "Boston" },
        id: 1
      }.to_json
      
      post '/a2a/rpc', request_body, { 'CONTENT_TYPE' => 'application/json' }
      
      expect(last_response).to be_ok
      
      response = JSON.parse(last_response.body)
      expect(response['result']['location']).to eq("Boston")
      expect(response['result']['temperature']).to eq("70°F")
    end
    
    it "handles invalid requests" do
      request_body = "invalid json"
      
      post '/a2a/rpc', request_body, { 'CONTENT_TYPE' => 'application/json' }
      
      expect(last_response.status).to eq(400)
      
      response = JSON.parse(last_response.body)
      expect(response['error']['code']).to eq(-32700)
    end
  end
  
  describe "GET /a2a/health" do
    it "returns health status" do
      get '/a2a/health'
      
      expect(last_response).to be_ok
      
      health = JSON.parse(last_response.body)
      expect(health['status']).to eq('healthy')
    end
  end
end
```

## Deployment

### Production Configuration

```ruby
# config/puma.rb
workers Integer(ENV['WEB_CONCURRENCY'] || 2)
threads_count = Integer(ENV['RAILS_MAX_THREADS'] || 5)
threads threads_count, threads_count

preload_app!

rackup      DefaultRackup
port        ENV['PORT']     || 3000
environment ENV['RACK_ENV'] || 'development'

on_worker_boot do
  # Worker specific setup for Rails applications
end
```

### Docker Deployment

```dockerfile
# Dockerfile
FROM ruby:3.2-alpine

# Install dependencies
RUN apk add --no-cache build-base

# Set working directory
WORKDIR /app

# Copy Gemfile
COPY Gemfile Gemfile.lock ./
RUN bundle install --deployment --without development test

# Copy application
COPY . .

# Expose port
EXPOSE 3000

# Start application
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
```

### Heroku Deployment

```ruby
# Procfile
web: bundle exec puma -C config/puma.rb
```

```bash
# Deploy to Heroku
heroku create weather-agent
heroku config:set RACK_ENV=production
heroku config:set A2A_LOG_LEVEL=info
git push heroku main
```

## Performance Optimization

### Connection Pooling

```ruby
# lib/connection_pool.rb
require 'connection_pool'

class ConnectionManager
  def self.redis_pool
    @redis_pool ||= ConnectionPool.new(size: 5, timeout: 5) do
      Redis.new(url: ENV['REDIS_URL'])
    end
  end
  
  def self.http_pool
    @http_pool ||= ConnectionPool.new(size: 10, timeout: 5) do
      Faraday.new do |conn|
        conn.adapter Faraday.default_adapter
      end
    end
  end
end
```

### Caching

```ruby
# lib/cache.rb
class SimpleCache
  def initialize
    @cache = {}
    @expires = {}
  end
  
  def get(key)
    return nil if expired?(key)
    @cache[key]
  end
  
  def set(key, value, ttl = 300)
    @cache[key] = value
    @expires[key] = Time.now + ttl
  end
  
  private
  
  def expired?(key)
    return true unless @expires[key]
    Time.now > @expires[key]
  end
end

# Use in agents
class CachedWeatherAgent < WeatherAgent
  def initialize
    @cache = SimpleCache.new
  end
  
  a2a_method "get_current_weather" do |params|
    location = params[:location]
    cache_key = "weather:#{location.downcase}"
    
    cached_result = @cache.get(cache_key)
    return cached_result if cached_result
    
    result = super(params)
    @cache.set(cache_key, result, 600)  # Cache for 10 minutes
    result
  end
end
```

This Sinatra integration guide provides a complete foundation for building lightweight A2A agents with Sinatra, covering everything from basic setup to production deployment.