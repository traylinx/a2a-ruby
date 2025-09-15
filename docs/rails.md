# Rails Integration Guide

This guide covers comprehensive integration of the A2A Ruby SDK with Ruby on Rails applications.

## Table of Contents

- [Installation and Setup](#installation-and-setup)
- [Configuration](#configuration)
- [Creating A2A Agents](#creating-a2a-agents)
- [Routing and Controllers](#routing-and-controllers)
- [Database Integration](#database-integration)
- [Authentication](#authentication)
- [Background Jobs](#background-jobs)
- [Testing](#testing)
- [Deployment](#deployment)
- [Advanced Features](#advanced-features)

## Installation and Setup

### Add to Gemfile

```ruby
# Gemfile
gem 'a2a-ruby'

# Optional: Add background job support
gem 'sidekiq'  # or 'resque', 'delayed_job'

# Optional: Add Redis for caching and storage
gem 'redis'
gem 'redis-rails'
```

### Install and Generate Configuration

```bash
bundle install

# Generate A2A configuration and routes
rails generate a2a:install

# Generate database migrations (if using database storage)
rails generate a2a:migration

# Run migrations
rails db:migrate
```

### Generated Files

The install generator creates:

```
config/initializers/a2a.rb          # A2A configuration
config/routes.rb                    # A2A routes (updated)
db/migrate/xxx_create_a2a_tasks.rb  # Task storage migration
db/migrate/xxx_create_a2a_push_notification_configs.rb  # Push notification migration
```

## Configuration

### Basic Configuration

```ruby
# config/initializers/a2a.rb
A2A.configure do |config|
  # Protocol settings
  config.protocol_version = "0.3.0"
  config.default_transport = "JSONRPC"
  
  # Rails-specific settings
  config.rails_integration = true
  config.mount_path = "/a2a"
  
  # Storage backend
  config.storage_backend = :database  # Use ActiveRecord
  
  # Authentication
  config.server_auth_strategy = :jwt
  config.jwt_secret = Rails.application.secret_key_base
  
  # Performance
  config.enable_metrics = Rails.env.production?
  config.log_level = Rails.env.production? ? :info : :debug
  
  # Background jobs
  config.background_job_adapter = :sidekiq  # or :active_job
end
```

### Environment-Specific Configuration

```ruby
# config/initializers/a2a.rb
A2A.configure do |config|
  case Rails.env
  when 'development'
    config.log_level = :debug
    config.log_requests = true
    config.storage_backend = :memory
    config.force_ssl = false
  when 'test'
    config.log_level = :warn
    config.storage_backend = :memory
    config.background_job_adapter = :inline
  when 'production'
    config.log_level = :info
    config.storage_backend = :database
    config.force_ssl = true
    config.enable_metrics = true
    config.rate_limit_enabled = true
  end
end
```

### Environment Variables

```bash
# .env (development)
A2A_PROTOCOL_VERSION=0.3.0
A2A_LOG_LEVEL=debug
A2A_STORAGE_BACKEND=memory

# .env.production
A2A_PROTOCOL_VERSION=0.3.0
A2A_LOG_LEVEL=info
A2A_STORAGE_BACKEND=database
A2A_FORCE_SSL=true
A2A_ENABLE_METRICS=true
A2A_JWT_SECRET=your-production-secret
```

## Creating A2A Agents

### Generate Agent Controller

```bash
# Generate a new A2A agent
rails generate a2a:agent weather

# This creates:
# app/controllers/weather_agent_controller.rb
# spec/controllers/weather_agent_controller_spec.rb
# README_weather_agent.md
```

### Basic Agent Controller

```ruby
# app/controllers/weather_agent_controller.rb
class WeatherAgentController < ApplicationController
  include A2A::Rails::ControllerHelpers
  
  # Agent metadata
  a2a_config(
    name: "Weather Service Agent",
    description: "Provides comprehensive weather information and forecasts",
    version: "1.0.0",
    provider: {
      name: "Weather Corp",
      url: "https://weather-corp.com"
    }
  )
  
  # Define agent skills
  a2a_skill "current_weather" do |skill|
    skill.description = "Get current weather conditions for any location"
    skill.tags = ["weather", "current", "conditions"]
    skill.examples = [
      "What's the weather in New York?",
      "Current conditions in Tokyo",
      "Weather for San Francisco"
    ]
    skill.input_modes = ["text"]
    skill.output_modes = ["text", "structured"]
  end
  
  a2a_skill "weather_forecast" do |skill|
    skill.description = "Get multi-day weather forecast"
    skill.tags = ["weather", "forecast", "prediction"]
    skill.examples = [
      "5-day forecast for London",
      "Weather forecast for next week in Paris"
    ]
    skill.input_modes = ["text"]
    skill.output_modes = ["text", "structured"]
  end
  
  # A2A method implementations
  a2a_method "get_current_weather" do |params|
    location = params[:location]
    
    # Validate parameters
    raise A2A::Errors::InvalidParams, "Location is required" if location.blank?
    
    # Fetch weather data
    weather_data = WeatherService.current(location)
    
    {
      location: location,
      temperature: weather_data.temperature,
      condition: weather_data.condition,
      humidity: weather_data.humidity,
      wind_speed: weather_data.wind_speed,
      timestamp: Time.current.iso8601
    }
  rescue WeatherService::LocationNotFound => e
    raise A2A::Errors::InvalidParams, "Location '#{location}' not found"
  rescue WeatherService::ServiceError => e
    raise A2A::Errors::ServiceUnavailable, "Weather service temporarily unavailable"
  end
  
  a2a_method "get_weather_forecast", streaming: true do |params|
    location = params[:location]
    days = params[:days] || 5
    
    # Validate parameters
    raise A2A::Errors::InvalidParams, "Location is required" if location.blank?
    raise A2A::Errors::InvalidParams, "Days must be between 1 and 10" unless (1..10).include?(days)
    
    Enumerator.new do |yielder|
      begin
        # Initial status
        yielder << task_status_update("working", "Fetching #{days}-day forecast for #{location}")
        
        # Fetch forecast data
        forecast = WeatherService.forecast(location, days)
        
        forecast.each_with_index do |day_forecast, index|
          # Format day forecast
          day_data = {
            date: day_forecast.date.iso8601,
            high_temperature: day_forecast.high_temp,
            low_temperature: day_forecast.low_temp,
            condition: day_forecast.condition,
            precipitation_chance: day_forecast.precipitation_chance
          }
          
          # Yield forecast message
          message = A2A::Types::Message.new(
            message_id: SecureRandom.uuid,
            role: "agent",
            parts: [
              A2A::Types::TextPart.new(
                text: "Day #{index + 1}: #{day_forecast.condition}, High: #{day_forecast.high_temp}°F, Low: #{day_forecast.low_temp}°F"
              ),
              A2A::Types::DataPart.new(data: day_data)
            ]
          )
          yielder << message
          
          # Progress update
          progress = ((index + 1).to_f / days * 100).round
          yielder << task_status_update("working", "Progress: #{progress}%", progress)
        end
        
        # Completion
        yielder << task_status_update("completed", "#{days}-day forecast complete")
      rescue WeatherService::LocationNotFound => e
        yielder << task_status_update("failed", "Location '#{location}' not found")
      rescue WeatherService::ServiceError => e
        yielder << task_status_update("failed", "Weather service error: #{e.message}")
      rescue => e
        Rails.logger.error "Unexpected error in weather forecast: #{e.message}"
        yielder << task_status_update("failed", "Internal server error")
      end
    end
  end
  
  # Authentication required method
  a2a_method "get_premium_forecast", auth_required: true do |params|
    # Only available to authenticated users
    return { error: "Premium subscription required" } unless current_user&.premium?
    
    location = params[:location]
    detailed_forecast = WeatherService.premium_forecast(location, current_user.id)
    
    {
      location: location,
      detailed_forecast: detailed_forecast,
      user_id: current_user.id
    }
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

### Advanced Agent with File Handling

```ruby
class DocumentProcessorController < ApplicationController
  include A2A::Rails::ControllerHelpers
  
  a2a_config(
    name: "Document Processor",
    description: "Process and analyze documents",
    version: "2.0.0"
  )
  
  a2a_skill "document_analysis" do |skill|
    skill.description = "Analyze document content and extract insights"
    skill.tags = ["document", "analysis", "extraction"]
    skill.input_modes = ["file", "text"]
    skill.output_modes = ["structured", "text"]
  end
  
  a2a_method "analyze_document", streaming: true do |params|
    Enumerator.new do |yielder|
      begin
        # Extract file from message parts
        file_part = extract_file_part(params)
        raise A2A::Errors::InvalidParams, "Document file is required" unless file_part
        
        # Initial status
        yielder << task_status_update("working", "Processing document: #{file_part.file.name}")
        
        # Create background job for processing
        job = DocumentAnalysisJob.perform_later(
          task_id: params[:task_id],
          file_data: file_part.file.bytes,
          file_name: file_part.file.name,
          mime_type: file_part.file.mime_type
        )
        
        # Return task with job reference
        yielder << task_status_update("working", "Document queued for processing", 10)
        
        # The job will update task status via push notifications
      rescue => e
        Rails.logger.error "Document analysis error: #{e.message}"
        yielder << task_status_update("failed", "Failed to process document: #{e.message}")
      end
    end
  end
  
  private
  
  def extract_file_part(params)
    message = params[:message]
    return nil unless message&.dig(:parts)
    
    message[:parts].find { |part| part[:kind] == 'file' }
  end
end
```

## Routing and Controllers

### Automatic Routes

The A2A Rails engine automatically provides these routes:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount A2A::Engine => "/a2a"
  
  # This provides:
  # POST /a2a/rpc                    - JSON-RPC endpoint
  # GET  /a2a/agent-card             - Agent card discovery
  # GET  /a2a/capabilities           - Capabilities listing
  # GET  /a2a/health                 - Health check
  # GET  /a2a/metrics                - Metrics (if enabled)
end
```

### Custom Routes

```ruby
# config/routes.rb
Rails.application.routes.draw do
  # Mount A2A engine
  mount A2A::Engine => "/a2a"
  
  # Custom A2A agent routes
  namespace :api do
    namespace :v1 do
      resources :agents, only: [:index, :show] do
        member do
          post :rpc
          get :card
        end
      end
    end
  end
end
```

### Custom Agent Endpoints

```ruby
class Api::V1::AgentsController < ApplicationController
  include A2A::Rails::ControllerHelpers
  
  def index
    agents = [
      { name: "Weather Agent", path: "/a2a/weather" },
      { name: "Document Processor", path: "/a2a/documents" }
    ]
    render json: agents
  end
  
  def show
    agent_class = "#{params[:id].camelize}AgentController".constantize
    agent = agent_class.new
    
    card = agent.generate_agent_card(
      url: "#{request.base_url}/api/v1/agents/#{params[:id]}/rpc"
    )
    
    render json: card.to_h
  end
  
  def rpc
    agent_class = "#{params[:id].camelize}AgentController".constantize
    agent = agent_class.new
    
    handle_a2a_rpc_request(agent)
  end
end
```

## Database Integration

### Models

The A2A Rails integration provides ActiveRecord models:

```ruby
# app/models/a2a/task.rb (generated)
class A2A::Task < ApplicationRecord
  self.table_name = 'a2a_tasks'
  
  has_many :push_notification_configs, 
           class_name: 'A2A::PushNotificationConfig',
           dependent: :destroy
  
  validates :task_id, presence: true, uniqueness: true
  validates :context_id, presence: true
  validates :status, presence: true
  
  scope :active, -> { where(status: ['submitted', 'working']) }
  scope :completed, -> { where(status: ['completed', 'canceled', 'failed']) }
  
  def status_object
    @status_object ||= A2A::Types::TaskStatus.from_h(JSON.parse(status))
  end
  
  def status_object=(status)
    self.status = status.to_h.to_json
    @status_object = status
  end
end

# app/models/a2a/push_notification_config.rb (generated)
class A2A::PushNotificationConfig < ApplicationRecord
  self.table_name = 'a2a_push_notification_configs'
  
  belongs_to :task, class_name: 'A2A::Task'
  
  validates :config_id, presence: true, uniqueness: { scope: :task_id }
  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp }
end
```

### Custom Models

```ruby
# app/models/weather_request.rb
class WeatherRequest < ApplicationRecord
  belongs_to :user, optional: true
  
  validates :location, presence: true
  validates :request_type, inclusion: { in: %w[current forecast] }
  
  scope :recent, -> { where('created_at > ?', 1.day.ago) }
  
  def self.create_from_a2a_task(task, user: nil)
    create!(
      task_id: task.id,
      location: task.params['location'],
      request_type: task.params['type'] || 'current',
      user: user,
      status: task.status.state
    )
  end
end
```

### Database Queries

```ruby
class WeatherAgentController < ApplicationController
  include A2A::Rails::ControllerHelpers
  
  a2a_method "get_weather_history" do |params|
    user_id = current_user&.id
    location = params[:location]
    
    # Query recent weather requests
    recent_requests = WeatherRequest.joins(:user)
                                  .where(users: { id: user_id })
                                  .where(location: location)
                                  .recent
                                  .limit(10)
    
    {
      location: location,
      recent_requests: recent_requests.map do |request|
        {
          date: request.created_at.iso8601,
          type: request.request_type,
          status: request.status
        }
      end
    }
  end
end
```

## Authentication

### Devise Integration

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception
  
  # A2A authentication
  def authenticate_a2a_request
    return unless a2a_request?
    
    token = request.headers['Authorization']&.sub(/^Bearer /, '')
    
    if token.present?
      authenticate_with_jwt(token)
    else
      render json: { error: 'Authentication required' }, status: :unauthorized
    end
  end
  
  private
  
  def a2a_request?
    request.path.start_with?('/a2a/')
  end
  
  def authenticate_with_jwt(token)
    begin
      payload = JWT.decode(token, Rails.application.secret_key_base, true, algorithm: 'HS256')
      user_id = payload[0]['user_id']
      @current_user = User.find(user_id)
    rescue JWT::DecodeError => e
      render json: { error: 'Invalid token' }, status: :unauthorized
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'User not found' }, status: :unauthorized
    end
  end
end

# Agent controller with authentication
class SecureAgentController < ApplicationController
  include A2A::Rails::ControllerHelpers
  
  before_action :authenticate_a2a_request
  
  a2a_method "secure_operation" do |params|
    # Access authenticated user
    {
      message: "Hello, #{current_user.name}!",
      user_id: current_user.id,
      operation: params[:operation]
    }
  end
end
```

### Custom Authentication Strategy

```ruby
# lib/a2a/auth/api_key_strategy.rb
class A2A::Auth::ApiKeyStrategy
  def initialize(app)
    @app = app
  end
  
  def call(env)
    request = ActionDispatch::Request.new(env)
    
    if a2a_request?(request)
      api_key = request.headers['X-API-Key']
      
      unless valid_api_key?(api_key)
        return [401, {}, [{ error: 'Invalid API key' }.to_json]]
      end
      
      # Set user context
      env['a2a.user'] = User.find_by(api_key: api_key)
    end
    
    @app.call(env)
  end
  
  private
  
  def a2a_request?(request)
    request.path.start_with?('/a2a/')
  end
  
  def valid_api_key?(api_key)
    api_key.present? && User.exists?(api_key: api_key)
  end
end

# config/application.rb
config.middleware.use A2A::Auth::ApiKeyStrategy
```

## Background Jobs

### Sidekiq Integration

```ruby
# app/jobs/weather_forecast_job.rb
class WeatherForecastJob < ApplicationJob
  queue_as :a2a_tasks
  
  def perform(task_id, location, days)
    task_manager = A2A::Server::TaskManager.new
    
    begin
      # Update status
      task_manager.update_task_status(task_id,
        A2A::Types::TaskStatus.new(state: "working", message: "Fetching forecast data")
      )
      
      # Fetch forecast
      forecast_data = WeatherService.detailed_forecast(location, days)
      
      # Process each day
      forecast_data.each_with_index do |day_data, index|
        # Create artifact for each day
        artifact = A2A::Types::Artifact.new(
          artifact_id: SecureRandom.uuid,
          name: "Day #{index + 1} Forecast",
          parts: [A2A::Types::DataPart.new(data: day_data)]
        )
        
        # Update task with artifact
        task_manager.add_task_artifact(task_id, artifact)
        
        # Progress update
        progress = ((index + 1).to_f / days * 100).round
        task_manager.update_task_status(task_id,
          A2A::Types::TaskStatus.new(
            state: "working",
            message: "Processed day #{index + 1}/#{days}",
            progress: progress
          )
        )
      end
      
      # Complete task
      task_manager.update_task_status(task_id,
        A2A::Types::TaskStatus.new(
          state: "completed",
          message: "Forecast complete",
          result: { days_processed: days }
        )
      )
    rescue => e
      Rails.logger.error "Weather forecast job failed: #{e.message}"
      
      task_manager.update_task_status(task_id,
        A2A::Types::TaskStatus.new(
          state: "failed",
          message: "Forecast failed: #{e.message}",
          error: { message: e.message, type: e.class.name }
        )
      )
    end
  end
end
```

### Active Job Integration

```ruby
# app/jobs/document_analysis_job.rb
class DocumentAnalysisJob < ApplicationJob
  queue_as :document_processing
  
  retry_on StandardError, wait: :exponentially_longer, attempts: 3
  
  def perform(task_id:, file_data:, file_name:, mime_type:)
    task_manager = A2A::Server::TaskManager.new
    
    begin
      # Decode file data
      file_content = Base64.decode64(file_data)
      
      # Update status
      task_manager.update_task_status(task_id,
        A2A::Types::TaskStatus.new(
          state: "working",
          message: "Analyzing document: #{file_name}",
          progress: 10
        )
      )
      
      # Process document based on type
      analysis_result = case mime_type
      when 'application/pdf'
        analyze_pdf(file_content)
      when 'text/plain'
        analyze_text(file_content)
      when /^image\//
        analyze_image(file_content)
      else
        raise "Unsupported file type: #{mime_type}"
      end
      
      # Create result artifact
      result_artifact = A2A::Types::Artifact.new(
        artifact_id: SecureRandom.uuid,
        name: "Analysis Result",
        description: "Document analysis results for #{file_name}",
        parts: [A2A::Types::DataPart.new(data: analysis_result)]
      )
      
      task_manager.add_task_artifact(task_id, result_artifact)
      
      # Complete task
      task_manager.update_task_status(task_id,
        A2A::Types::TaskStatus.new(
          state: "completed",
          message: "Document analysis complete",
          result: { 
            file_name: file_name,
            analysis_type: analysis_result[:type],
            confidence: analysis_result[:confidence]
          }
        )
      )
    rescue => e
      Rails.logger.error "Document analysis failed: #{e.message}"
      
      task_manager.update_task_status(task_id,
        A2A::Types::TaskStatus.new(
          state: "failed",
          message: "Analysis failed: #{e.message}",
          error: { message: e.message, type: e.class.name }
        )
      )
    end
  end
  
  private
  
  def analyze_pdf(content)
    # PDF analysis logic
    { type: 'pdf', pages: 10, text_length: 5000, confidence: 0.95 }
  end
  
  def analyze_text(content)
    # Text analysis logic
    { type: 'text', word_count: content.split.size, confidence: 1.0 }
  end
  
  def analyze_image(content)
    # Image analysis logic
    { type: 'image', format: 'jpeg', dimensions: '1920x1080', confidence: 0.88 }
  end
end
```

## Testing

### RSpec Configuration

```ruby
# spec/rails_helper.rb
require 'spec_helper'
require 'a2a/testing'

RSpec.configure do |config|
  config.include A2A::Testing::Helpers
  config.include A2A::Testing::Matchers
  
  # Clean up A2A data between tests
  config.before(:each) do
    A2A::Server::TaskManager.new.clear_all_tasks if Rails.env.test?
  end
end
```

### Controller Testing

```ruby
# spec/controllers/weather_agent_controller_spec.rb
RSpec.describe WeatherAgentController, type: :controller do
  include A2A::Testing::Helpers
  
  describe "A2A methods" do
    describe "get_current_weather" do
      it "returns current weather data" do
        # Mock weather service
        weather_data = double(
          temperature: "72°F",
          condition: "Sunny",
          humidity: "45%",
          wind_speed: "5 mph"
        )
        allow(WeatherService).to receive(:current).with("New York").and_return(weather_data)
        
        # Create A2A request
        request = build_a2a_request("get_current_weather", { location: "New York" })
        
        # Send request
        post :handle_a2a_rpc, body: request.to_json, as: :json
        
        # Verify response
        expect(response).to have_http_status(:ok)
        
        json_response = JSON.parse(response.body)
        expect(json_response).to have_key('result')
        expect(json_response['result']['location']).to eq("New York")
        expect(json_response['result']['temperature']).to eq("72°F")
      end
      
      it "handles invalid location" do
        allow(WeatherService).to receive(:current).and_raise(WeatherService::LocationNotFound)
        
        request = build_a2a_request("get_current_weather", { location: "Invalid" })
        post :handle_a2a_rpc, body: request.to_json, as: :json
        
        expect(response).to have_http_status(:bad_request)
        
        json_response = JSON.parse(response.body)
        expect(json_response).to have_key('error')
        expect(json_response['error']['code']).to eq(-32602)
      end
    end
    
    describe "get_weather_forecast" do
      it "streams forecast data" do
        forecast_data = [
          double(date: Date.current, high_temp: 75, low_temp: 60, condition: "Sunny"),
          double(date: Date.current + 1, high_temp: 73, low_temp: 58, condition: "Cloudy")
        ]
        allow(WeatherService).to receive(:forecast).and_return(forecast_data)
        
        request = build_a2a_request("get_weather_forecast", { 
          location: "San Francisco", 
          days: 2,
          task_id: "test-task-123",
          context_id: "test-context-123"
        })
        
        # Test streaming response
        responses = []
        controller = WeatherAgentController.new
        
        controller.get_weather_forecast(request[:params]).each do |response|
          responses << response
        end
        
        # Verify responses
        expect(responses).to include(
          an_instance_of(A2A::Types::TaskStatusUpdateEvent),
          an_instance_of(A2A::Types::Message)
        )
        
        status_events = responses.select { |r| r.is_a?(A2A::Types::TaskStatusUpdateEvent) }
        expect(status_events.last.status.state).to eq("completed")
      end
    end
  end
end
```

### Integration Testing

```ruby
# spec/integration/a2a_integration_spec.rb
RSpec.describe "A2A Integration", type: :request do
  let(:client) { A2A::Client::HttpClient.new("http://localhost:3000/a2a") }
  
  describe "agent card discovery" do
    it "returns valid agent card" do
      get "/a2a/agent-card"
      
      expect(response).to have_http_status(:ok)
      
      card_data = JSON.parse(response.body)
      expect(card_data).to include(
        'name' => be_present,
        'description' => be_present,
        'version' => be_present,
        'skills' => be_an(Array)
      )
    end
  end
  
  describe "JSON-RPC endpoint" do
    it "handles weather requests" do
      message = A2A::Types::Message.new(
        message_id: SecureRandom.uuid,
        role: "user",
        parts: [A2A::Types::TextPart.new(text: "Weather in Boston")]
      )
      
      rpc_request = {
        jsonrpc: "2.0",
        method: "message/send",
        params: { message: message.to_h },
        id: 1
      }
      
      post "/a2a/rpc", params: rpc_request.to_json, 
           headers: { 'Content-Type' => 'application/json' }
      
      expect(response).to have_http_status(:ok)
      
      json_response = JSON.parse(response.body)
      expect(json_response).to have_key('result')
    end
  end
end
```

### Background Job Testing

```ruby
# spec/jobs/weather_forecast_job_spec.rb
RSpec.describe WeatherForecastJob, type: :job do
  include ActiveJob::TestHelper
  
  let(:task_id) { "test-task-123" }
  let(:location) { "Seattle" }
  let(:days) { 3 }
  
  it "processes weather forecast successfully" do
    forecast_data = [
      { date: Date.current, high_temp: 70, low_temp: 55 },
      { date: Date.current + 1, high_temp: 68, low_temp: 53 },
      { date: Date.current + 2, high_temp: 72, low_temp: 57 }
    ]
    allow(WeatherService).to receive(:detailed_forecast).and_return(forecast_data)
    
    expect {
      WeatherForecastJob.perform_now(task_id, location, days)
    }.to change { A2A::Task.count }.by(0)  # Task should be updated, not created
    
    # Verify task completion
    task_manager = A2A::Server::TaskManager.new
    task = task_manager.get_task(task_id)
    expect(task.status.state).to eq("completed")
    expect(task.artifacts.size).to eq(3)  # One artifact per day
  end
  
  it "handles service errors gracefully" do
    allow(WeatherService).to receive(:detailed_forecast).and_raise(WeatherService::ServiceError)
    
    WeatherForecastJob.perform_now(task_id, location, days)
    
    task_manager = A2A::Server::TaskManager.new
    task = task_manager.get_task(task_id)
    expect(task.status.state).to eq("failed")
    expect(task.status.error).to be_present
  end
end
```

## Deployment

### Production Configuration

```ruby
# config/environments/production.rb
Rails.application.configure do
  # A2A production settings
  config.after_initialize do
    A2A.configure do |a2a_config|
      a2a_config.log_level = :info
      a2a_config.enable_metrics = true
      a2a_config.force_ssl = true
      a2a_config.rate_limit_enabled = true
      a2a_config.storage_backend = :database
      
      # Redis for caching and sessions
      a2a_config.redis_url = ENV['REDIS_URL']
      
      # Background jobs
      a2a_config.background_job_adapter = :sidekiq
    end
  end
end
```

### Docker Configuration

```dockerfile
# Dockerfile
FROM ruby:3.2-alpine

# Install dependencies
RUN apk add --no-cache \
    build-base \
    postgresql-dev \
    redis

# Set working directory
WORKDIR /app

# Copy Gemfile
COPY Gemfile Gemfile.lock ./
RUN bundle install --deployment --without development test

# Copy application
COPY . .

# Precompile assets
RUN bundle exec rails assets:precompile

# Expose port
EXPOSE 3000

# Start application
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
```

### Kubernetes Deployment

```yaml
# k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: weather-agent
spec:
  replicas: 3
  selector:
    matchLabels:
      app: weather-agent
  template:
    metadata:
      labels:
        app: weather-agent
    spec:
      containers:
      - name: weather-agent
        image: weather-agent:latest
        ports:
        - containerPort: 3000
        env:
        - name: RAILS_ENV
          value: "production"
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: weather-agent-secrets
              key: database-url
        - name: REDIS_URL
          valueFrom:
            secretKeyRef:
              name: weather-agent-secrets
              key: redis-url
        - name: A2A_JWT_SECRET
          valueFrom:
            secretKeyRef:
              name: weather-agent-secrets
              key: jwt-secret
        livenessProbe:
          httpGet:
            path: /a2a/health
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /a2a/health
            port: 3000
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: weather-agent-service
spec:
  selector:
    app: weather-agent
  ports:
  - port: 80
    targetPort: 3000
  type: LoadBalancer
```

### Health Checks

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount A2A::Engine => "/a2a"
  
  # Custom health check
  get '/health', to: 'health#check'
end

# app/controllers/health_controller.rb
class HealthController < ApplicationController
  def check
    health_status = {
      status: 'healthy',
      timestamp: Time.current.iso8601,
      version: Rails.application.class.module_parent_name,
      checks: {
        database: check_database,
        redis: check_redis,
        a2a: check_a2a_service
      }
    }
    
    overall_status = health_status[:checks].values.all? { |check| check[:status] == 'healthy' }
    health_status[:status] = overall_status ? 'healthy' : 'unhealthy'
    
    status_code = overall_status ? :ok : :service_unavailable
    render json: health_status, status: status_code
  end
  
  private
  
  def check_database
    ActiveRecord::Base.connection.execute('SELECT 1')
    { status: 'healthy', response_time: measure_time { ActiveRecord::Base.connection.execute('SELECT 1') } }
  rescue => e
    { status: 'unhealthy', error: e.message }
  end
  
  def check_redis
    Redis.current.ping
    { status: 'healthy', response_time: measure_time { Redis.current.ping } }
  rescue => e
    { status: 'unhealthy', error: e.message }
  end
  
  def check_a2a_service
    task_manager = A2A::Server::TaskManager.new
    test_task = task_manager.create_task(type: 'health_check')
    task_manager.get_task(test_task.id)
    { status: 'healthy' }
  rescue => e
    { status: 'unhealthy', error: e.message }
  end
  
  def measure_time
    start_time = Time.current
    yield
    ((Time.current - start_time) * 1000).round(2)
  end
end
```

## Advanced Features

### Caching

```ruby
# config/initializers/a2a.rb
A2A.configure do |config|
  config.enable_caching = true
  config.cache_backend = :rails
  config.cache_ttl = 300  # 5 minutes
end

# Agent with caching
class WeatherAgentController < ApplicationController
  include A2A::Rails::ControllerHelpers
  
  a2a_method "get_current_weather" do |params|
    location = params[:location]
    cache_key = "weather:current:#{location.downcase}"
    
    Rails.cache.fetch(cache_key, expires_in: 10.minutes) do
      WeatherService.current(location)
    end
  end
end
```

### Rate Limiting

```ruby
# config/initializers/a2a.rb
A2A.configure do |config|
  config.rate_limit_enabled = true
  config.rate_limit_requests = 100
  config.rate_limit_window = 60  # seconds
  config.rate_limit_storage = :redis
end

# Custom rate limiting
class RateLimitedAgentController < ApplicationController
  include A2A::Rails::ControllerHelpers
  
  before_action :check_rate_limit
  
  private
  
  def check_rate_limit
    client_id = request.headers['X-Client-ID'] || request.remote_ip
    
    rate_limiter = A2A::RateLimiter.new(
      key: "agent:#{controller_name}:#{client_id}",
      limit: 50,
      window: 60
    )
    
    unless rate_limiter.allowed?
      render json: {
        jsonrpc: "2.0",
        error: {
          code: -32006,
          message: "Rate limit exceeded",
          data: { retry_after: rate_limiter.retry_after }
        },
        id: params[:id]
      }, status: :too_many_requests
    end
  end
end
```

### Monitoring and Metrics

```ruby
# config/initializers/a2a.rb
A2A.configure do |config|
  config.enable_metrics = true
  config.metrics_backend = :prometheus
end

# Custom metrics
class MetricsCollector
  def self.record_weather_request(location, success, duration)
    WEATHER_REQUEST_COUNTER.increment(
      labels: { location: location, success: success }
    )
    
    WEATHER_REQUEST_DURATION.observe(
      duration,
      labels: { location: location }
    )
  end
end

# In agent controller
a2a_method "get_current_weather" do |params|
  start_time = Time.current
  
  begin
    result = WeatherService.current(params[:location])
    MetricsCollector.record_weather_request(params[:location], true, Time.current - start_time)
    result
  rescue => e
    MetricsCollector.record_weather_request(params[:location], false, Time.current - start_time)
    raise
  end
end
```

This comprehensive Rails integration guide covers all aspects of using the A2A Ruby SDK in Rails applications, from basic setup to advanced production features.