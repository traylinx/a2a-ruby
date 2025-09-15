# frozen_string_literal: true

##
# Test helpers for A2A protocol testing
# Following patterns from a2a-python test utilities
#
module A2AHelpers
  # Test data generators

  # Generate a test UUID
  def test_uuid
    SecureRandom.uuid
  end

  # Generate an ISO8601 timestamp for testing
  def test_timestamp
    Time.now.utc.iso8601
  end

  # Generate test authentication token
  def test_auth_token
    "test_token_#{SecureRandom.hex(16)}"
  end

  # Generate test API key
  def test_api_key
    "ak_test_#{SecureRandom.hex(20)}"
  end

  # JSON-RPC helpers
  # Build a JSON-RPC 2.0 request (equivalent to a2a-python test helpers)
  def build_json_rpc_request(method, params = {}, id = 1)
    {
      jsonrpc: "2.0",
      method: method,
      params: params,
      id: id
    }
  end

  # Build a JSON-RPC 2.0 batch request
  def build_json_rpc_batch(*requests)
    requests.map.with_index do |req, index|
      build_json_rpc_request(req[:method], req[:params] || {}, index + 1)
    end
  end

  # Build an A2A agent card for testing
  def build_agent_card(**overrides)
    {
      name: "Test Agent",
      description: "A test agent for A2A protocol testing",
      version: "1.0.0",
      url: "https://test-agent.example.com/a2a",
      preferredTransport: "JSONRPC",
      protocolVersion: "0.3.0",
      skills: [
        {
          id: "test_skill",
          name: "Test Skill",
          description: "A test skill",
          tags: %w[test example]
        }
      ],
      capabilities: {
        streaming: true,
        pushNotifications: true,
        stateTransitionHistory: true
      },
      defaultInputModes: ["text/plain", "application/json"],
      defaultOutputModes: ["text/plain", "application/json"]
    }.merge(overrides)
  end

  # Build an A2A message for testing
  def build_message(role: "user", text: "Hello, agent!", **overrides)
    {
      messageId: SecureRandom.uuid,
      role: role,
      kind: "message",
      parts: [
        {
          kind: "text",
          text: text
        }
      ]
    }.merge(overrides)
  end

  # Build an A2A task for testing
  def build_task(state: "submitted", **overrides)
    {
      id: SecureRandom.uuid,
      contextId: SecureRandom.uuid,
      kind: "task",
      status: {
        state: state,
        updatedAt: Time.now.utc.iso8601
      }
    }.merge(overrides)
  end

  # Build a task status update event
  def build_task_status_update(task_id:, context_id:, state:, **overrides)
    {
      taskId: task_id,
      contextId: context_id,
      status: {
        state: state,
        updatedAt: Time.now.utc.iso8601
      }
    }.merge(overrides)
  end

  # Build a task artifact update event
  def build_task_artifact_update(task_id:, context_id:, artifact_id:, **overrides)
    {
      taskId: task_id,
      contextId: context_id,
      artifact: {
        artifactId: artifact_id,
        parts: [
          {
            kind: "text",
            text: "Test artifact content"
          }
        ]
      },
      append: false
    }.merge(overrides)
  end

  # Mock an A2A client with predefined responses
  def mock_a2a_client(responses = {})
    client = instance_double(A2A::Client::HttpClient)

    # Set up default responses
    allow(client).to receive_messages(send_message: build_message(role: "agent"), get_task: build_task,
                                      cancel_task: build_task(state: "canceled"), get_card: build_agent_card)

    # Override with custom responses - only for valid methods
    valid_methods = [:send_message, :get_task, :cancel_task, :get_card, :resubscribe, 
                     :set_task_push_notification_config, :get_task_push_notification_config,
                     :list_task_push_notification_configs, :delete_task_push_notification_config]
    
    responses.each do |method, response|
      if valid_methods.include?(method.to_sym)
        allow(client).to receive(method).and_return(response)
      end
    end

    client
  end

  # Stub HTTP requests for A2A endpoints
  def stub_a2a_request(method:, url:, response_body: {}, status: 200)
    stub_request(method, url)
      .to_return(
        status: status,
        body: response_body.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  # Stub A2A JSON-RPC request
  def stub_a2a_rpc_request(rpc_method:, url:, response: {}, error: nil)
    response_body = if error
                      {
                        jsonrpc: "2.0",
                        error: error,
                        id: 1
                      }
                    else
                      {
                        jsonrpc: "2.0",
                        result: response,
                        id: 1
                      }
                    end

    stub_request(:post, url)
      .with(
        body: hash_including(
          jsonrpc: "2.0",
          method: rpc_method
        ),
        headers: { "Content-Type" => "application/json" }
      )
      .to_return(
        status: error ? 400 : 200,
        body: response_body.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  # Expect a successful A2A JSON-RPC response
  def expect_a2a_success(response, expected_result = nil)
    expect(response).to have_key("jsonrpc")
    expect(response["jsonrpc"]).to eq("2.0")
    expect(response).to have_key("result")
    expect(response["result"]).to eq(expected_result) if expected_result
    expect(response).not_to have_key("error")
  end

  # Expect an A2A JSON-RPC error response
  def expect_a2a_error(response, error_code)
    expect(response).to have_key("jsonrpc")
    expect(response["jsonrpc"]).to eq("2.0")
    expect(response).to have_key("error")
    expect(response["error"]["code"]).to eq(error_code)
    expect(response).not_to have_key("result")
  end

  # Protocol validation helpers

  # Validate JSON-RPC 2.0 request structure
  def validate_json_rpc_request(request)
    begin
      expect(request).to be_valid_json_rpc_request
    rescue RSpec::Expectations::ExpectationNotMetError => e
      raise RSpec::Expectations::ExpectationNotMetError, 
            "JSON-RPC request validation failed: #{e.message}\nRequest: #{request.inspect}"
    end
  end

  # Validate JSON-RPC 2.0 response structure
  def validate_json_rpc_response(response)
    begin
      expect(response).to be_valid_json_rpc_response
    rescue RSpec::Expectations::ExpectationNotMetError => e
      raise RSpec::Expectations::ExpectationNotMetError, 
            "JSON-RPC response validation failed: #{e.message}\nResponse: #{response.inspect}"
    end
  end

  # Validate A2A agent card structure
  def validate_agent_card(card)
    begin
      expect(card).to be_valid_agent_card
    rescue RSpec::Expectations::ExpectationNotMetError => e
      raise RSpec::Expectations::ExpectationNotMetError, 
            "Agent card validation failed: #{e.message}\nCard: #{card.inspect}"
    end
  end

  # Validate A2A message structure
  def validate_a2a_message(message)
    begin
      expect(message).to be_valid_a2a_message
    rescue RSpec::Expectations::ExpectationNotMetError => e
      raise RSpec::Expectations::ExpectationNotMetError, 
            "A2A message validation failed: #{e.message}\nMessage: #{message.inspect}"
    end
  end

  # Validate A2A task structure
  def validate_a2a_task(task)
    begin
      expect(task).to be_valid_a2a_task
    rescue RSpec::Expectations::ExpectationNotMetError => e
      raise RSpec::Expectations::ExpectationNotMetError, 
            "A2A task validation failed: #{e.message}\nTask: #{task.inspect}"
    end
  end

  # Test server helpers

  # Create a test A2A server instance
  def create_test_server(port: nil)
    port ||= find_available_port
    TestA2AServer.new(port: port)
  end

  # Find an available port for testing
  def find_available_port
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    server.close
    port
  end

  # Create a test agent class
  def create_test_agent_class(&block)
    Class.new do
      include A2A::Server::Agent

      instance_eval(&block) if block_given?
    end
  end

  # Authentication helpers

  # Create OAuth2 test credentials
  def create_oauth2_credentials(client_id: nil, client_secret: nil, token_url: nil)
    {
      client_id: client_id || "test_client_#{SecureRandom.hex(8)}",
      client_secret: client_secret || "test_secret_#{SecureRandom.hex(16)}",
      token_url: token_url || "https://auth.example.com/token"
    }
  end

  # Create JWT test token
  def create_jwt_token(payload: {}, secret: nil)
    secret ||= "test_secret_#{SecureRandom.hex(32)}"
    now = Time.now
    default_payload = {
      sub: "test_user",
      iat: now.to_i,
      exp: (now + 3600).to_i  # 1 hour from now
    }

    # Simple JWT creation for testing (in real implementation, use JWT gem)
    header = Base64.urlsafe_encode64({ alg: "HS256", typ: "JWT" }.to_json)
    payload_encoded = Base64.urlsafe_encode64(default_payload.merge(payload).to_json)
    signature = Base64.urlsafe_encode64("fake_signature_for_testing")

    "#{header}.#{payload_encoded}.#{signature}"
  end

  # Streaming helpers

  # Create a test SSE stream
  def create_test_sse_stream(*events)
    Enumerator.new do |yielder|
      events.each do |event|
        sse_data = format_sse_event(event)
        yielder << sse_data
      end
    end
  end

  # Format data as Server-Sent Event
  def format_sse_event(data, event_type: nil, id: nil)
    lines = []
    lines << "id: #{id}" if id
    lines << "event: #{event_type}" if event_type

    lines << if data.is_a?(Hash) || data.is_a?(Array)
               "data: #{data.to_json}"
             else
               "data: #{data}"
             end

    "#{lines.join("\n")}\n\n"
  end

  # Parse SSE event from string
  def parse_sse_event(sse_string)
    lines = sse_string.strip.split("\n")
    event = {}

    lines.each do |line|
      if line.start_with?("id: ")
        event[:id] = line[4..]
      elsif line.start_with?("event: ")
        event[:event] = line[7..]
      elsif line.start_with?("data: ")
        data = line[6..]
        begin
          event[:data] = JSON.parse(data)
        rescue JSON::ParserError
          event[:data] = data
        end
      end
    end

    event
  end

  # Error testing helpers

  # Create a JSON-RPC error response
  def create_json_rpc_error(code:, message:, data: nil, id: 1)
    A2A::Protocol::JsonRpc.build_error_response(
      code: code,
      message: message,
      data: data,
      id: id
    )
  end

  # Create an A2A-specific error
  def create_a2a_error(error_class, message: nil, **options)
    error_class.new(message, **options)
  end

  # Performance testing helpers

  # Measure execution time
  def measure_time
    start_time = Time.now
    result = yield
    end_time = Time.now

    {
      result: result,
      duration: end_time - start_time,
      duration_ms: ((end_time - start_time) * 1000).round(2)
    }
  end

  # Measure memory usage (requires get_process_mem gem)
  def measure_memory
    return { result: yield, memory_mb: 0 } unless defined?(GetProcessMem)

    mem_before = GetProcessMem.new.mb
    result = yield
    mem_after = GetProcessMem.new.mb

    {
      result: result,
      memory_mb: (mem_after - mem_before).round(2)
    }
  end

  # Concurrency testing helpers

  # Run block concurrently with specified number of threads
  def run_concurrently(thread_count: 10)
    threads = []
    results = []
    mutex = Mutex.new

    thread_count.times do |i|
      threads << Thread.new do
        result = yield(i)
        mutex.synchronize { results << result }
      end
    end

    threads.each(&:join)
    results
  end

  # Load testing helper
  def load_test(duration: 5, concurrent_requests: 10, &block)  # duration in seconds
    start_time = Time.now
    end_time = start_time + duration
    results = []

    while Time.now < end_time
      batch_results = run_concurrently(thread_count: concurrent_requests, &block)
      results.concat(batch_results)
      sleep(0.1) # Small delay between batches
    end

    {
      total_requests: results.length,
      duration: duration,
      requests_per_second: (results.length / duration.to_f).round(2),
      results: results
    }
  end

  # Fixture helpers

  # Load fixture file
  def load_fixture(filename)
    fixture_path = File.join(File.dirname(__FILE__), "..", "fixtures", filename)

    raise "Fixture file not found: #{fixture_path}" unless File.exist?(fixture_path)

    content = File.read(fixture_path)

    case File.extname(filename)
    when ".json"
      JSON.parse(content)
    when ".yml", ".yaml"
      YAML.safe_load(content)
    else
      content
    end
  end

  # Save fixture file (for generating test data)
  def save_fixture(filename, data)
    fixture_path = File.join(File.dirname(__FILE__), "..", "fixtures", filename)
    FileUtils.mkdir_p(File.dirname(fixture_path))

    content = case File.extname(filename)
              when ".json"
                JSON.pretty_generate(data)
              when ".yml", ".yaml"
                data.to_yaml
              else
                data.to_s
              end

    File.write(fixture_path, content)
  end

  # WebMock helpers

  # Stub all A2A endpoints for an agent
  def stub_a2a_agent(base_url:, agent_card: nil, responses: {})
    agent_card ||= build_agent_card(url: "#{base_url}/a2a")

    # Stub agent card endpoint
    stub_request(:get, "#{base_url}/agent-card")
      .to_return(
        status: 200,
        body: agent_card.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    # Stub RPC endpoint with custom responses
    responses.each do |method, response|
      stub_a2a_rpc_request(
        rpc_method: method,
        url: "#{base_url}/a2a",
        response: response
      )
    end
  end

  # Verify A2A request was made
  def expect_a2a_request(method:, url:, params: nil)
    expected_body = {
      jsonrpc: "2.0",
      method: method
    }
    expected_body[:params] = params if params

    expect(WebMock).to have_requested(:post, url)
      .with(body: hash_including(expected_body))
  end

  # VCR helpers

  # Use VCR cassette with A2A-specific configuration
  def with_a2a_vcr_cassette(name, **options, &block)
    default_options = {
      record: :once,
      match_requests_on: %i[method uri body],
      allow_unused_http_interactions: false
    }

    VCR.use_cassette(name, default_options.merge(options), &block)
  end

  # Environment helpers

  # Temporarily set environment variables
  def with_env(env_vars)
    original_values = {}

    env_vars.each do |key, value|
      original_values[key] = ENV.fetch(key, nil)
      ENV[key] = value
    end

    begin
      yield
    ensure
      original_values.each do |key, value|
        if value.nil?
          ENV.delete(key)
        else
          ENV[key] = value
        end
      end
    end
  end

  # Configuration helpers

  # Create test A2A configuration
  def create_test_config(**overrides)
    default_config = {
      log_level: :debug,
      timeout: 5,
      max_retries: 2,
      enable_streaming: true,
      enable_push_notifications: true
    }

    A2A::Configuration.new(default_config.merge(overrides))
  end

  # Temporarily override A2A configuration
  def with_a2a_config(**config_overrides)
    original_config = A2A.configuration.dup

    begin
      config_overrides.each do |key, value|
        A2A.configuration.send("#{key}=", value)
      end

      yield
    ensure
      A2A.instance_variable_set(:@configuration, original_config)
    end
  end
end

# Test server class for integration testing
class TestA2AServer
  attr_reader :port, :url

  def initialize(port: nil)
    @port = port || find_available_port
    @url = "http://127.0.0.1:#{@port}"
    @server = nil
    @thread = nil
  end

  def start
    return if running?

    @server = TCPServer.new("127.0.0.1", @port)
    @thread = Thread.new { run_server }

    # Wait for server to start
    sleep(0.1) until running?
  end

  def stop
    return unless running?

    @server&.close
    @thread&.kill
    @server = nil
    @thread = nil
  end

  def running?
    @server && !@server.closed? && @thread&.alive?
  end

  private

  def find_available_port
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    server.close
    port
  end

  def run_server
    loop do
      client = @server.accept

      # Simple HTTP server for testing
      request = client.gets

      if request&.include?("GET /agent-card")
        handle_agent_card_request(client)
      elsif request&.include?("POST /a2a")
        handle_rpc_request(client)
      else
        send_404_response(client)
      end

      client.close
    end
  rescue StandardError
    # Server stopped
  end

  def handle_agent_card_request(client)
    agent_card = {
      name: "Test Server Agent",
      description: "A test server for A2A protocol testing",
      version: "1.0.0",
      url: "#{@url}/a2a",
      preferredTransport: "JSONRPC",
      skills: [],
      capabilities: { streaming: true },
      defaultInputModes: ["text/plain"],
      defaultOutputModes: ["text/plain"]
    }

    send_json_response(client, agent_card)
  end

  def handle_rpc_request(client)
    # Read request body
    content_length = 0
    while (line = client.gets.chomp) != ""
      content_length = line.split(":")[1].strip.to_i if line.start_with?("Content-Length:")
    end

    body = client.read(content_length) if content_length > 0

    # Simple echo response for testing
    response = {
      jsonrpc: "2.0",
      result: { message: "Test response", echo: body },
      id: 1
    }

    send_json_response(client, response)
  end

  def send_json_response(client, data)
    json = data.to_json
    response = [
      "HTTP/1.1 200 OK",
      "Content-Type: application/json",
      "Content-Length: #{json.bytesize}",
      "Connection: close",
      "",
      json
    ].join("\r\n")

    client.write(response)
  end

  def send_404_response(client)
    response = [
      "HTTP/1.1 404 Not Found",
      "Content-Length: 0",
      "Connection: close",
      "",
      ""
    ].join("\r\n")

    client.write(response)
  end
end

RSpec.configure do |config|
  config.include A2AHelpers
end
