# Plain Ruby Usage Guide

This guide covers using the A2A Ruby SDK in plain Ruby applications without web frameworks.

## Table of Contents

- [Basic Setup](#basic-setup)
- [Client Usage](#client-usage)
- [Server Implementation](#server-implementation)
- [Command Line Tools](#command-line-tools)
- [Background Services](#background-services)
- [Testing](#testing)
- [Advanced Patterns](#advanced-patterns)
- [Performance Considerations](#performance-considerations)

## Basic Setup

### Installation

```ruby
# Gemfile
source 'https://rubygems.org'

gem 'a2a-ruby'

# Optional dependencies
gem 'redis'      # For storage and caching
gem 'sidekiq'    # For background jobs
gem 'thor'       # For CLI applications
gem 'logger'     # Enhanced logging
```

### Basic Configuration

```ruby
# config/a2a_config.rb
require 'a2a'

A2A.configure do |config|
  config.protocol_version = "0.3.0"
  config.default_transport = "JSONRPC"
  config.streaming_enabled = true
  config.log_level = ENV['A2A_LOG_LEVEL']&.to_sym || :info
  config.storage_backend = ENV['A2A_STORAGE_BACKEND']&.to_sym || :memory
  
  # Configure logger
  config.logger = Logger.new(STDOUT)
  config.logger.level = Logger::INFO
end
```

### Project Structure

```
my_a2a_app/
├── Gemfile
├── config/
│   └── a2a_config.rb
├── lib/
│   ├── agents/
│   │   ├── weather_agent.rb
│   │   └── calculator_agent.rb
│   ├── clients/
│   │   └── weather_client.rb
│   ├── services/
│   │   └── weather_service.rb
│   └── cli/
│       └── weather_cli.rb
├── bin/
│   ├── weather_server
│   └── weather_client
└── spec/
    └── agents/
        └── weather_agent_spec.rb
```

## Client Usage

### Basic Client

```ruby
# lib/clients/weather_client.rb
require_relative '../config/a2a_config'

class WeatherClient
  def initialize(endpoint_url, auth: nil)
    @client = A2A::Client::HttpClient.new(endpoint_url, auth: auth)
  end
  
  def get_current_weather(location)
    message = A2A::Types::Message.new(
      message_id: SecureRandom.uuid,
      role: "user",
      parts: [A2A::Types::TextPart.new(text: "Current weather in #{location}")]
    )
    
    # Send message and get response
    response = @client.send_message(message, streaming: false)
    
    case response
    when A2A::Types::Message
      parse_weather_response(response)
    when A2A::Types::Task
      wait_for_task_completion(response.id)
    else
      raise "Unexpected response type: #{response.class}"
    end
  end
  
  def get_weather_forecast(location, days: 5)
    message = A2A::Types::Message.new(
      message_id: SecureRandom.uuid,
      role: "user",
      parts: [
        A2A::Types::TextPart.new(text: "#{days}-day forecast for #{location}"),
        A2A::Types::DataPart.new(data: { location: location, days: days })
      ]
    )
    
    forecast_data = []
    
    @client.send_message(message, streaming: true) do |response|
      case response
      when A2A::Types::Message
        forecast_data << parse_forecast_day(response)
      when A2A::Types::TaskStatusUpdateEvent
        puts "Status: #{response.status.state} - #{response.status.message}"
      end
    end
    
    forecast_data
  end
  
  def get_agent_info
    card = @client.get_card
    {
      name: card.name,
      description: card.description,
      version: card.version,
      skills: card.skills.map { |skill| skill.name }
    }
  end
  
  private
  
  def parse_weather_response(message)
    text_part = message.parts.find { |part| part.is_a?(A2A::Types::TextPart) }
    data_part = message.parts.find { |part| part.is_a?(A2A::Types::DataPart) }
    
    {
      description: text_part&.text,
      data: data_part&.data
    }
  end
  
  def parse_forecast_day(message)
    data_part = message.parts.find { |part| part.is_a?(A2A::Types::DataPart) }
    data_part&.data
  end
  
  def wait_for_task_completion(task_id)
    loop do
      task = @client.get_task(task_id)
      
      case task.status.state
      when 'completed'
        return task.status.result
      when 'failed', 'canceled'
        raise "Task #{task.status.state}: #{task.status.message}"
      else
        puts "Task status: #{task.status.state}"
        sleep(1)
      end
    end
  end
end
```

### Advanced Client with Authentication

```ruby
# lib/clients/authenticated_client.rb
class AuthenticatedWeatherClient < WeatherClient
  def initialize(endpoint_url, client_id:, client_secret:, token_url:)
    auth = A2A::Client::Auth::OAuth2.new(
      client_id: client_id,
      client_secret: client_secret,
      token_url: token_url
    )
    
    super(endpoint_url, auth: auth)
  end
  
  def get_premium_forecast(location, days: 10)
    # This method requires authentication
    message = A2A::Types::Message.new(
      message_id: SecureRandom.uuid,
      role: "user",
      parts: [
        A2A::Types::TextPart.new(text: "Premium #{days}-day forecast for #{location}"),
        A2A::Types::DataPart.new(data: { 
          location: location, 
          days: days, 
          premium: true 
        })
      ]
    )
    
    @client.send_message(message, streaming: false)
  end
end
```

### Client with File Upload

```ruby
# lib/clients/document_client.rb
class DocumentClient
  def initialize(endpoint_url)
    @client = A2A::Client::HttpClient.new(endpoint_url)
  end
  
  def analyze_document(file_path)
    # Read file content
    file_content = File.read(file_path)
    file_name = File.basename(file_path)
    mime_type = detect_mime_type(file_path)
    
    # Create file part
    file_part = A2A::Types::FilePart.new(
      file: A2A::Types::FileWithBytes.new(
        name: file_name,
        mime_type: mime_type,
        bytes: Base64.encode64(file_content)
      )
    )
    
    message = A2A::Types::Message.new(
      message_id: SecureRandom.uuid,
      role: "user",
      parts: [
        A2A::Types::TextPart.new(text: "Please analyze this document"),
        file_part
      ]
    )
    
    analysis_results = []
    
    @client.send_message(message, streaming: true) do |response|
      case response
      when A2A::Types::Message
        analysis_results << response
      when A2A::Types::TaskStatusUpdateEvent
        puts "Analysis progress: #{response.status.progress}%" if response.status.progress
      end
    end
    
    analysis_results
  end
  
  private
  
  def detect_mime_type(file_path)
    case File.extname(file_path).downcase
    when '.txt' then 'text/plain'
    when '.json' then 'application/json'
    when '.pdf' then 'application/pdf'
    when '.jpg', '.jpeg' then 'image/jpeg'
    when '.png' then 'image/png'
    else 'application/octet-stream'
    end
  end
end
```

## Server Implementation

### Basic Agent Server

```ruby
# lib/agents/weather_agent.rb
require_relative '../services/weather_service'

class WeatherAgent
  include A2A::Server::Agent
  
  a2a_config(
    name: "Weather Agent",
    description: "Provides weather information and forecasts",
    version: "1.0.0"
  )
  
  a2a_skill "current_weather" do |skill|
    skill.description = "Get current weather conditions"
    skill.tags = ["weather", "current"]
    skill.examples = ["Weather in New York", "Current conditions"]
  end
  
  a2a_method "get_current_weather" do |params|
    location = params[:location]
    
    raise A2A::Errors::InvalidParams, "Location required" if location.nil? || location.empty?
    
    weather_data = WeatherService.current(location)
    
    {
      location: location,
      temperature: weather_data.temperature,
      condition: weather_data.condition,
      humidity: weather_data.humidity,
      timestamp: Time.now.iso8601
    }
  rescue WeatherService::LocationNotFound => e
    raise A2A::Errors::InvalidParams, "Location not found: #{location}"
  rescue WeatherService::ServiceError => e
    raise A2A::Errors::ServiceUnavailable, "Weather service unavailable"
  end
  
  a2a_method "get_weather_forecast", streaming: true do |params|
    location = params[:location]
    days = params[:days] || 5
    
    Enumerator.new do |yielder|
      begin
        yielder << status_update(params, "working", "Fetching forecast for #{location}")
        
        forecast = WeatherService.forecast(location, days)
        
        forecast.each_with_index do |day_data, index|
          message = A2A::Types::Message.new(
            message_id: SecureRandom.uuid,
            role: "agent",
            parts: [
              A2A::Types::TextPart.new(text: format_forecast_day(day_data)),
              A2A::Types::DataPart.new(data: day_data.to_h)
            ]
          )
          yielder << message
          
          progress = ((index + 1).to_f / days * 100).round
          yielder << status_update(params, "working", "Day #{index + 1}/#{days}", progress)
        end
        
        yielder << status_update(params, "completed", "Forecast complete")
      rescue => e
        yielder << status_update(params, "failed", "Error: #{e.message}")
      end
    end
  end
  
  private
  
  def status_update(params, state, message = nil, progress = nil)
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
  
  def format_forecast_day(day_data)
    "#{day_data.date}: #{day_data.condition}, High: #{day_data.high_temp}°F, Low: #{day_data.low_temp}°F"
  end
end
```

### HTTP Server

```ruby
# lib/servers/http_server.rb
require 'webrick'
require 'json'

class A2AHttpServer
  def initialize(port: 8080, agents: {})
    @port = port
    @agents = agents
    @server = WEBrick::HTTPServer.new(Port: @port)
    
    setup_routes
  end
  
  def start
    puts "Starting A2A server on port #{@port}"
    
    trap('INT') { @server.shutdown }
    @server.start
  end
  
  private
  
  def setup_routes
    # JSON-RPC endpoint
    @server.mount_proc '/a2a/rpc' do |req, res|
      handle_rpc_request(req, res)
    end
    
    # Agent card endpoint
    @server.mount_proc '/a2a/agent-card' do |req, res|
      handle_agent_card_request(req, res)
    end
    
    # Health check
    @server.mount_proc '/a2a/health' do |req, res|
      handle_health_request(req, res)
    end
    
    # Agent list
    @server.mount_proc '/a2a/agents' do |req, res|
      handle_agents_list_request(req, res)
    end
  end
  
  def handle_rpc_request(req, res)
    res['Content-Type'] = 'application/json'
    res['Access-Control-Allow-Origin'] = '*'
    
    begin
      request_body = req.body
      json_rpc_request = A2A::Protocol::JsonRpc.parse_request(request_body)
      
      # Route to appropriate agent
      agent = get_agent_for_request(json_rpc_request)
      response = agent.handle_a2a_request(json_rpc_request)
      
      res.body = response.to_json
    rescue A2A::Errors::A2AError => e
      res.status = 400
      res.body = e.to_json_rpc_error.to_json
    rescue => e
      puts "Server error: #{e.message}"
      res.status = 500
      res.body = {
        jsonrpc: "2.0",
        error: { code: -32603, message: "Internal error" },
        id: nil
      }.to_json
    end
  end
  
  def handle_agent_card_request(req, res)
    res['Content-Type'] = 'application/json'
    
    # Return combined agent card or specific agent
    agent_name = req.query['agent']
    
    if agent_name && @agents[agent_name]
      agent = @agents[agent_name].new
      card = agent.generate_agent_card(
        url: "http://localhost:#{@port}/a2a"
      )
      res.body = card.to_h.to_json
    else
      # Return combined capabilities
      combined_card = generate_combined_agent_card
      res.body = combined_card.to_json
    end
  end
  
  def handle_health_request(req, res)
    res['Content-Type'] = 'application/json'
    
    health_status = {
      status: 'healthy',
      timestamp: Time.now.iso8601,
      agents: @agents.keys,
      version: A2A::VERSION
    }
    
    res.body = health_status.to_json
  end
  
  def handle_agents_list_request(req, res)
    res['Content-Type'] = 'application/json'
    
    agents_info = @agents.map do |name, agent_class|
      {
        name: name,
        class: agent_class.name,
        endpoint: "http://localhost:#{@port}/a2a/rpc"
      }
    end
    
    res.body = { agents: agents_info }.to_json
  end
  
  def get_agent_for_request(json_rpc_request)
    # Simple routing - use first available agent
    # In production, you might route based on method name or other criteria
    agent_class = @agents.values.first
    raise A2A::Errors::ServiceUnavailable, "No agents available" unless agent_class
    
    agent_class.new
  end
  
  def generate_combined_agent_card
    # Combine capabilities from all agents
    all_skills = []
    
    @agents.each do |name, agent_class|
      agent = agent_class.new
      card = agent.generate_agent_card
      all_skills.concat(card.skills)
    end
    
    {
      name: "Multi-Agent Server",
      description: "Combined A2A agent server",
      version: "1.0.0",
      skills: all_skills.map(&:to_h),
      url: "http://localhost:#{@port}/a2a"
    }
  end
end
```

### Background Task Processing

```ruby
# lib/services/task_processor.rb
class TaskProcessor
  def initialize
    @task_manager = A2A::Server::TaskManager.new
    @running = false
  end
  
  def start
    @running = true
    puts "Starting task processor..."
    
    while @running
      process_pending_tasks
      sleep(1)
    end
  end
  
  def stop
    @running = false
    puts "Stopping task processor..."
  end
  
  private
  
  def process_pending_tasks
    # Get tasks that need processing
    pending_tasks = @task_manager.get_tasks_by_status(['submitted', 'working'])
    
    pending_tasks.each do |task|
      begin
        process_task(task)
      rescue => e
        puts "Error processing task #{task.id}: #{e.message}"
        
        @task_manager.update_task_status(task.id,
          A2A::Types::TaskStatus.new(
            state: "failed",
            message: "Processing error: #{e.message}",
            error: { message: e.message, type: e.class.name }
          )
        )
      end
    end
  end
  
  def process_task(task)
    case task.type
    when 'weather_forecast'
      process_weather_forecast_task(task)
    when 'document_analysis'
      process_document_analysis_task(task)
    else
      puts "Unknown task type: #{task.type}"
    end
  end
  
  def process_weather_forecast_task(task)
    params = task.params
    location = params['location']
    days = params['days'] || 5
    
    # Update status
    @task_manager.update_task_status(task.id,
      A2A::Types::TaskStatus.new(
        state: "working",
        message: "Fetching #{days}-day forecast for #{location}"
      )
    )
    
    # Simulate processing
    forecast_data = WeatherService.forecast(location, days)
    
    # Create artifacts for each day
    forecast_data.each_with_index do |day_data, index|
      artifact = A2A::Types::Artifact.new(
        artifact_id: SecureRandom.uuid,
        name: "Day #{index + 1} Forecast",
        parts: [A2A::Types::DataPart.new(data: day_data.to_h)]
      )
      
      @task_manager.add_task_artifact(task.id, artifact)
      
      # Progress update
      progress = ((index + 1).to_f / days * 100).round
      @task_manager.update_task_status(task.id,
        A2A::Types::TaskStatus.new(
          state: "working",
          message: "Processed day #{index + 1}/#{days}",
          progress: progress
        )
      )
    end
    
    # Complete task
    @task_manager.update_task_status(task.id,
      A2A::Types::TaskStatus.new(
        state: "completed",
        message: "Forecast complete",
        result: { days_processed: days, location: location }
      )
    )
  end
end
```

## Command Line Tools

### CLI Client

```ruby
# lib/cli/weather_cli.rb
require 'thor'
require_relative '../clients/weather_client'

class WeatherCLI < Thor
  desc "current LOCATION", "Get current weather for location"
  option :endpoint, default: "http://localhost:8080/a2a", desc: "A2A endpoint URL"
  option :format, default: "text", desc: "Output format (text, json)"
  def current(location)
    client = WeatherClient.new(options[:endpoint])
    
    begin
      weather = client.get_current_weather(location)
      
      case options[:format]
      when 'json'
        puts JSON.pretty_generate(weather)
      else
        puts format_weather_text(weather)
      end
    rescue => e
      puts "Error: #{e.message}"
      exit 1
    end
  end
  
  desc "forecast LOCATION", "Get weather forecast for location"
  option :endpoint, default: "http://localhost:8080/a2a", desc: "A2A endpoint URL"
  option :days, type: :numeric, default: 5, desc: "Number of days"
  option :format, default: "text", desc: "Output format (text, json)"
  def forecast(location)
    client = WeatherClient.new(options[:endpoint])
    
    begin
      forecast_data = client.get_weather_forecast(location, days: options[:days])
      
      case options[:format]
      when 'json'
        puts JSON.pretty_generate(forecast_data)
      else
        puts format_forecast_text(forecast_data)
      end
    rescue => e
      puts "Error: #{e.message}"
      exit 1
    end
  end
  
  desc "info", "Get agent information"
  option :endpoint, default: "http://localhost:8080/a2a", desc: "A2A endpoint URL"
  def info
    client = WeatherClient.new(options[:endpoint])
    
    begin
      agent_info = client.get_agent_info
      
      puts "Agent: #{agent_info[:name]}"
      puts "Description: #{agent_info[:description]}"
      puts "Version: #{agent_info[:version]}"
      puts "Skills: #{agent_info[:skills].join(', ')}"
    rescue => e
      puts "Error: #{e.message}"
      exit 1
    end
  end
  
  private
  
  def format_weather_text(weather)
    if weather[:data]
      data = weather[:data]
      "Weather in #{data['location']}: #{data['temperature']}, #{data['condition']}"
    else
      weather[:description] || "No weather data available"
    end
  end
  
  def format_forecast_text(forecast_data)
    return "No forecast data available" if forecast_data.empty?
    
    forecast_data.map do |day|
      next unless day
      
      if day['date']
        "#{day['date']}: #{day['condition']}, High: #{day['high_temperature']}, Low: #{day['low_temperature']}"
      else
        day.to_s
      end
    end.compact.join("\n")
  end
end
```

### Server CLI

```ruby
# lib/cli/server_cli.rb
require 'thor'
require_relative '../servers/http_server'
require_relative '../agents/weather_agent'
require_relative '../agents/calculator_agent'

class ServerCLI < Thor
  desc "start", "Start the A2A server"
  option :port, type: :numeric, default: 8080, desc: "Server port"
  option :agents, type: :array, default: ['weather'], desc: "Agents to load"
  def start
    agents = load_agents(options[:agents])
    
    server = A2AHttpServer.new(
      port: options[:port],
      agents: agents
    )
    
    puts "Starting server with agents: #{agents.keys.join(', ')}"
    server.start
  end
  
  desc "test", "Test agent functionality"
  option :agent, default: "weather", desc: "Agent to test"
  def test
    agent_class = get_agent_class(options[:agent])
    agent = agent_class.new
    
    puts "Testing #{agent_class.name}..."
    
    # Test agent card generation
    card = agent.generate_agent_card
    puts "Agent card: #{card.name} v#{card.version}"
    puts "Skills: #{card.skills.map(&:name).join(', ')}"
    
    # Test basic method (if available)
    if agent.respond_to?(:get_current_weather)
      begin
        result = agent.get_current_weather({ location: "Test City" })
        puts "Test method result: #{result}"
      rescue => e
        puts "Test method error: #{e.message}"
      end
    end
    
    puts "Test complete"
  end
  
  private
  
  def load_agents(agent_names)
    agents = {}
    
    agent_names.each do |name|
      agent_class = get_agent_class(name)
      agents[name] = agent_class if agent_class
    end
    
    agents
  end
  
  def get_agent_class(name)
    case name.downcase
    when 'weather'
      WeatherAgent
    when 'calculator'
      CalculatorAgent
    else
      puts "Unknown agent: #{name}"
      nil
    end
  end
end
```

### Executable Scripts

```ruby
#!/usr/bin/env ruby
# bin/weather_client

require_relative '../lib/cli/weather_cli'

WeatherCLI.start(ARGV)
```

```ruby
#!/usr/bin/env ruby
# bin/weather_server

require_relative '../lib/cli/server_cli'

ServerCLI.start(ARGV)
```

```bash
# Make scripts executable
chmod +x bin/weather_client
chmod +x bin/weather_server
```

## Background Services

### Service Daemon

```ruby
# lib/services/weather_daemon.rb
require 'logger'

class WeatherDaemon
  def initialize
    @logger = Logger.new(STDOUT)
    @running = false
    @task_processor = TaskProcessor.new
  end
  
  def start
    @logger.info "Starting Weather Daemon..."
    @running = true
    
    # Start task processor in background thread
    @task_thread = Thread.new { @task_processor.start }
    
    # Start HTTP server in background thread
    agents = { 'weather' => WeatherAgent }
    @server = A2AHttpServer.new(port: 8080, agents: agents)
    @server_thread = Thread.new { @server.start }
    
    # Main loop
    while @running
      perform_periodic_tasks
      sleep(60)  # Run every minute
    end
  end
  
  def stop
    @logger.info "Stopping Weather Daemon..."
    @running = false
    
    @task_processor.stop
    @server.shutdown if @server
    
    @task_thread.join if @task_thread
    @server_thread.join if @server_thread
  end
  
  private
  
  def perform_periodic_tasks
    # Cleanup old tasks
    cleanup_old_tasks
    
    # Update weather cache
    update_weather_cache
    
    # Log statistics
    log_statistics
  end
  
  def cleanup_old_tasks
    # Remove completed tasks older than 24 hours
    cutoff_time = Time.now - (24 * 60 * 60)
    
    # Implementation depends on storage backend
    @logger.debug "Cleaning up tasks older than #{cutoff_time}"
  end
  
  def update_weather_cache
    # Pre-populate cache with popular locations
    popular_locations = ['New York', 'London', 'Tokyo', 'Sydney']
    
    popular_locations.each do |location|
      begin
        WeatherService.current(location)
        @logger.debug "Updated cache for #{location}"
      rescue => e
        @logger.warn "Failed to update cache for #{location}: #{e.message}"
      end
    end
  end
  
  def log_statistics
    # Log basic statistics
    @logger.info "Daemon running, processed tasks: #{get_task_count}"
  end
  
  def get_task_count
    # Return number of processed tasks
    0  # Placeholder
  end
end
```

### Process Management

```ruby
# lib/process_manager.rb
class ProcessManager
  def self.daemonize(name, &block)
    # Fork process
    pid = fork do
      # Detach from terminal
      Process.setsid
      
      # Change working directory
      Dir.chdir('/')
      
      # Redirect standard streams
      $stdin.reopen('/dev/null')
      $stdout.reopen("/tmp/#{name}.log", 'a')
      $stderr.reopen("/tmp/#{name}.error.log", 'a')
      
      # Set up signal handlers
      trap('TERM') { exit }
      trap('INT') { exit }
      
      # Run the block
      yield
    end
    
    # Write PID file
    File.write("/tmp/#{name}.pid", pid)
    
    puts "Started #{name} daemon with PID #{pid}"
    pid
  end
  
  def self.stop_daemon(name)
    pid_file = "/tmp/#{name}.pid"
    
    if File.exist?(pid_file)
      pid = File.read(pid_file).to_i
      
      begin
        Process.kill('TERM', pid)
        puts "Stopped #{name} daemon (PID #{pid})"
        File.delete(pid_file)
      rescue Errno::ESRCH
        puts "Process #{pid} not found"
        File.delete(pid_file)
      end
    else
      puts "PID file not found for #{name}"
    end
  end
end

# Usage
ProcessManager.daemonize('weather_daemon') do
  daemon = WeatherDaemon.new
  daemon.start
end
```

## Testing

### Unit Testing

```ruby
# spec/agents/weather_agent_spec.rb
require 'rspec'
require_relative '../../lib/agents/weather_agent'

RSpec.describe WeatherAgent do
  let(:agent) { WeatherAgent.new }
  
  describe "#get_current_weather" do
    it "returns weather data for valid location" do
      allow(WeatherService).to receive(:current).with("Boston").and_return(
        OpenStruct.new(
          temperature: "70°F",
          condition: "Sunny",
          humidity: "50%"
        )
      )
      
      result = agent.get_current_weather({ location: "Boston" })
      
      expect(result[:location]).to eq("Boston")
      expect(result[:temperature]).to eq("70°F")
      expect(result[:condition]).to eq("Sunny")
    end
    
    it "raises error for missing location" do
      expect {
        agent.get_current_weather({})
      }.to raise_error(A2A::Errors::InvalidParams, "Location required")
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
        location: "Seattle",
        days: 2,
        task_id: "test-task",
        context_id: "test-context"
      }).each do |response|
        responses << response
      end
      
      # Verify we got status updates and messages
      status_events = responses.select { |r| r.is_a?(A2A::Types::TaskStatusUpdateEvent) }
      messages = responses.select { |r| r.is_a?(A2A::Types::Message) }
      
      expect(status_events).not_to be_empty
      expect(messages.size).to eq(2)  # One message per day
      
      # Check final status
      expect(status_events.last.status.state).to eq("completed")
    end
  end
end
```

### Integration Testing

```ruby
# spec/integration/client_server_spec.rb
require 'rspec'
require 'webrick'
require 'thread'
require_relative '../../lib/servers/http_server'
require_relative '../../lib/clients/weather_client'

RSpec.describe "Client-Server Integration" do
  let(:port) { 8081 }
  let(:server_url) { "http://localhost:#{port}/a2a" }
  let(:client) { WeatherClient.new(server_url) }
  
  before(:all) do
    # Start server in background
    agents = { 'weather' => WeatherAgent }
    @server = A2AHttpServer.new(port: port, agents: agents)
    
    @server_thread = Thread.new { @server.start }
    
    # Wait for server to start
    sleep(1)
  end
  
  after(:all) do
    @server.shutdown if @server
    @server_thread.join if @server_thread
  end
  
  it "handles weather requests end-to-end" do
    allow(WeatherService).to receive(:current).and_return(
      OpenStruct.new(
        temperature: "72°F",
        condition: "Sunny",
        humidity: "45%"
      )
    )
    
    result = client.get_current_weather("New York")
    
    expect(result[:data]['location']).to eq("New York")
    expect(result[:data]['temperature']).to eq("72°F")
  end
  
  it "retrieves agent information" do
    agent_info = client.get_agent_info
    
    expect(agent_info[:name]).to eq("Weather Agent")
    expect(agent_info[:skills]).to include("current_weather")
  end
end
```

## Advanced Patterns

### Connection Pooling

```ruby
# lib/utils/connection_pool.rb
require 'thread'

class ConnectionPool
  def initialize(size: 5, &block)
    @size = size
    @pool = Queue.new
    @factory = block
    
    @size.times { @pool << @factory.call }
  end
  
  def with_connection
    connection = @pool.pop
    
    begin
      yield connection
    ensure
      @pool << connection
    end
  end
end

# Usage
http_pool = ConnectionPool.new(size: 10) do
  Faraday.new do |conn|
    conn.adapter Faraday.default_adapter
  end
end

http_pool.with_connection do |http|
  response = http.get('https://api.example.com/weather')
end
```

### Circuit Breaker

```ruby
# lib/utils/circuit_breaker.rb
class CircuitBreaker
  STATES = [:closed, :open, :half_open].freeze
  
  def initialize(failure_threshold: 5, recovery_timeout: 60, success_threshold: 3)
    @failure_threshold = failure_threshold
    @recovery_timeout = recovery_timeout
    @success_threshold = success_threshold
    @failure_count = 0
    @success_count = 0
    @last_failure_time = nil
    @state = :closed
    @mutex = Mutex.new
  end
  
  def call(&block)
    @mutex.synchronize do
      case @state
      when :open
        if Time.now - @last_failure_time > @recovery_timeout
          @state = :half_open
          @success_count = 0
        else
          raise CircuitBreakerOpenError, "Circuit breaker is open"
        end
      end
    end
    
    begin
      result = yield
      on_success
      result
    rescue => e
      on_failure
      raise
    end
  end
  
  private
  
  def on_success
    @mutex.synchronize do
      @failure_count = 0
      
      if @state == :half_open
        @success_count += 1
        if @success_count >= @success_threshold
          @state = :closed
        end
      end
    end
  end
  
  def on_failure
    @mutex.synchronize do
      @failure_count += 1
      @last_failure_time = Time.now
      
      if @failure_count >= @failure_threshold
        @state = :open
      end
    end
  end
  
  class CircuitBreakerOpenError < StandardError; end
end
```

### Retry Logic

```ruby
# lib/utils/retry_helper.rb
class RetryHelper
  def self.with_retry(max_attempts: 3, delay: 1, backoff: 2, &block)
    attempts = 0
    
    begin
      attempts += 1
      yield
    rescue => e
      if attempts < max_attempts
        sleep(delay)
        delay *= backoff
        retry
      else
        raise e
      end
    end
  end
end

# Usage
RetryHelper.with_retry(max_attempts: 5, delay: 0.5) do
  client.get_current_weather("New York")
end
```

## Performance Considerations

### Memory Management

```ruby
# lib/utils/memory_monitor.rb
class MemoryMonitor
  def self.monitor(&block)
    start_memory = get_memory_usage
    
    result = yield
    
    end_memory = get_memory_usage
    memory_used = end_memory - start_memory
    
    puts "Memory used: #{memory_used} KB"
    
    result
  end
  
  private
  
  def self.get_memory_usage
    `ps -o rss= -p #{Process.pid}`.to_i
  end
end

# Usage
MemoryMonitor.monitor do
  client.get_weather_forecast("London", days: 10)
end
```

### Caching

```ruby
# lib/utils/simple_cache.rb
class SimpleCache
  def initialize(ttl: 300)
    @cache = {}
    @expires = {}
    @ttl = ttl
    @mutex = Mutex.new
  end
  
  def get(key)
    @mutex.synchronize do
      return nil if expired?(key)
      @cache[key]
    end
  end
  
  def set(key, value, ttl: nil)
    @mutex.synchronize do
      @cache[key] = value
      @expires[key] = Time.now + (ttl || @ttl)
    end
  end
  
  def clear
    @mutex.synchronize do
      @cache.clear
      @expires.clear
    end
  end
  
  private
  
  def expired?(key)
    return true unless @expires[key]
    Time.now > @expires[key]
  end
end

# Usage with weather service
class CachedWeatherService
  def initialize
    @cache = SimpleCache.new(ttl: 600)  # 10 minutes
  end
  
  def current(location)
    cache_key = "weather:#{location.downcase}"
    
    cached_result = @cache.get(cache_key)
    return cached_result if cached_result
    
    result = WeatherService.current(location)
    @cache.set(cache_key, result)
    result
  end
end
```

This comprehensive plain Ruby guide covers all aspects of using the A2A Ruby SDK in standalone Ruby applications, from basic client/server implementations to advanced patterns and performance optimization.