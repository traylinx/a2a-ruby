# frozen_string_literal: true

##
# Test doubles and mocks for A2A components
# Provides realistic test doubles for client and server components
#
module A2ATestDoubles
  # Client test doubles

  # Create a mock A2A client with configurable responses
  def mock_a2a_client(**options)
    client = instance_double(A2A::Client::HttpClient)

    # Default responses
    allow(client).to receive(:send_message) do |message, **opts|
      if opts[:streaming] || options[:streaming]
        create_test_sse_stream(
          build_message(role: "agent", text: "Response to: #{message[:parts]&.first&.dig(:text)}")
        )
      else
        build_message(role: "agent", text: "Response to: #{message[:parts]&.first&.dig(:text)}")
      end
    end

    allow(client).to receive(:get_task) do |task_id, **_opts|
      build_task(id: task_id, state: options[:task_state] || "completed")
    end

    allow(client).to receive(:cancel_task) do |task_id, **_opts|
      build_task(id: task_id, state: "canceled")
    end

    allow(client).to receive(:get_card) do |**_opts|
      build_agent_card(options[:agent_card] || {})
    end

    allow(client).to receive(:resubscribe) do |task_id, **_opts|
      create_test_sse_stream(
        build_task_status_update(
          task_id: task_id,
          context_id: test_uuid,
          state: "working"
        )
      )
    end

    # Push notification methods
    allow(client).to receive(:set_task_push_notification_config) do |task_id, config, **_opts|
      { id: test_uuid, taskId: task_id, **config }
    end

    allow(client).to receive(:get_task_push_notification_config) do |_task_id, config_id, **_opts|
      build(:push_notification_config, id: config_id)
    end

    allow(client).to receive(:list_task_push_notification_configs) do |_task_id, **_opts|
      [build(:push_notification_config)]
    end

    allow(client).to receive(:delete_task_push_notification_config).and_return(true)

    # Override with custom responses
    options[:responses]&.each do |method, response|
      allow(client).to receive(method).and_return(response)
    end

    client
  end

  # Create a mock A2A server agent
  def mock_a2a_agent(**options)
    agent = instance_double(TestAgent)

    # Mock agent methods
    allow(agent).to receive(:handle_a2a_request) do |request|
      case request.method
      when "message/send"
        A2A::Protocol::JsonRpc.build_response(
          result: build_message(role: "agent", text: "Mock response"),
          id: request.id
        )
      when "tasks/get"
        A2A::Protocol::JsonRpc.build_response(
          result: build_task(id: request.params["id"]),
          id: request.id
        )
      when "tasks/cancel"
        A2A::Protocol::JsonRpc.build_response(
          result: build_task(id: request.params["id"], state: "canceled"),
          id: request.id
        )
      else
        A2A::Protocol::JsonRpc.build_error_response(
          code: A2A::Protocol::JsonRpc::METHOD_NOT_FOUND,
          message: "Method not found",
          id: request.id
        )
      end
    end

    allow(agent).to receive(:generate_agent_card) do
      build_agent_card(options[:agent_card] || {})
    end

    agent
  end

  # Create a mock task manager
  def mock_task_manager(**options)
    task_manager = instance_double(A2A::Server::TaskManager)

    allow(task_manager).to receive(:create_task) do |**params|
      build_task(**params)
    end

    allow(task_manager).to receive(:get_task) do |task_id|
      if options[:tasks]&.key?(task_id)
        options[:tasks][task_id]
      else
        build_task(id: task_id)
      end
    end

    allow(task_manager).to receive(:update_task_status) do |task_id, status|
      task = build_task(id: task_id, status: status)
      options[:tasks] ||= {}
      options[:tasks][task_id] = task
      task
    end

    allow(task_manager).to receive(:cancel_task) do |task_id|
      task = build_task(id: task_id, state: "canceled")
      options[:tasks] ||= {}
      options[:tasks][task_id] = task
      task
    end

    allow(task_manager).to receive(:add_task_artifact) do |task_id, artifact|
      task = get_task(task_id)
      task[:artifacts] ||= []
      task[:artifacts] << artifact
      task
    end

    task_manager
  end

  # Create a mock storage backend
  def mock_storage_backend(**options)
    storage = instance_double(A2A::Server::Storage::Base)
    data = options[:data] || {}

    allow(storage).to receive(:save_task) do |task|
      data[task[:id]] = task
      task
    end

    allow(storage).to receive(:get_task) do |task_id|
      data[task_id]
    end

    allow(storage).to receive(:delete_task) do |task_id|
      data.delete(task_id)
    end

    allow(storage).to receive(:list_tasks) do |**filters|
      tasks = data.values

      tasks = tasks.select { |task| task.dig(:status, :state) == filters[:state] } if filters[:state]

      tasks = tasks.select { |task| task[:context_id] == filters[:context_id] } if filters[:context_id]

      tasks
    end

    allow(storage).to receive(:save_push_notification_config) do |config|
      config[:id] ||= test_uuid
      data["pn_#{config[:id]}"] = config
      config
    end

    allow(storage).to receive(:get_push_notification_config) do |config_id|
      data["pn_#{config_id}"]
    end

    allow(storage).to receive(:delete_push_notification_config) do |config_id|
      data.delete("pn_#{config_id}")
    end

    storage
  end

  # Create a mock HTTP client (Faraday)
  def mock_http_client(**options)
    http_client = instance_double(Faraday::Connection)

    allow(http_client).to receive(:post) do |path, _body, _headers|
      response_body = options[:responses]&.dig(path) || {
        jsonrpc: "2.0",
        result: { message: "Mock response" },
        id: 1
      }

      response = instance_double(Faraday::Response)
      allow(response).to receive_messages(status: 200, body: response_body,
        headers: { "Content-Type" => "application/json" }, success?: true)

      response
    end

    allow(http_client).to receive(:get) do |path, _params, _headers|
      response_body = if path.include?("agent-card")
                        build_agent_card
                      else
                        options[:get_responses]&.dig(path) || { message: "Mock GET response" }
                      end

      response = instance_double(Faraday::Response)
      allow(response).to receive_messages(status: 200, body: response_body,
        headers: { "Content-Type" => "application/json" }, success?: true)

      response
    end

    http_client
  end

  # Create a mock authentication strategy
  def mock_auth_strategy(**options)
    auth = instance_double(AuthStrategy)

    allow(auth).to receive(:authenticate) do |request|
      raise A2A::Errors::AuthenticationError, "Authentication failed" if options[:should_fail]

      request.headers ||= {}
      request.headers["Authorization"] = options[:token] || "Bearer mock_token"
      request
    end

    allow(auth).to receive(:valid_token?) do |token|
      !options[:should_fail] && token == (options[:token] || "Bearer mock_token")
    end

    auth
  end

  # Create a mock middleware
  def mock_middleware(**_options)
    Class.new do
      def initialize(app)
        @app = app
      end

      def call(env)
        # Add mock middleware behavior
        env[:mock_middleware_called] = true
        @app.call(env)
      end
    end
  end

  # Create a mock SSE connection
  def mock_sse_connection(**options)
    connection = instance_double(SSEConnection)

    allow(connection).to receive(:stream) do |&block|
      events = options[:events] || [
        build_task_status_update(
          task_id: test_uuid,
          context_id: test_uuid,
          state: "working"
        )
      ]

      events.each { |event| block.call(format_sse_event(event)) }
    end

    allow(connection).to receive(:close).and_return(true)
    allow(connection).to receive(:closed?) { options[:closed] || false }

    connection
  end

  # Create a mock gRPC client
  def mock_grpc_client(**_options)
    return nil unless defined?(GRPC)

    grpc_client = instance_double(GRPCClient)

    allow(grpc_client).to receive(:send_message) do |_request|
      # Mock gRPC response
      response = double("GRPCResponse")
      allow(response).to receive(:result).and_return(
        build_message(role: "agent", text: "gRPC response")
      )
      response
    end

    allow(grpc_client).to receive(:get_task) do |request|
      response = double("GRPCResponse")
      allow(response).to receive(:task).and_return(build_task(id: request.task_id))
      response
    end

    grpc_client
  end

  # Create a mock push notification sender
  def mock_push_notification_sender(**options)
    sender = instance_double(A2A::Server::PushNotificationManager)

    allow(sender).to receive(:send_notification) do |config, event|
      raise A2A::Errors::ClientError, "Failed to send notification" if options[:should_fail]

      { success: true, config_id: config[:id], event_type: event.class.name }
    end

    allow(sender).to receive(:register_config) do |_task_id, config|
      config[:id] ||= test_uuid
      config
    end

    allow(sender).to receive(:unregister_config).and_return(true)

    sender
  end

  # Create a mock Rails controller for testing Rails integration
  def mock_rails_controller(**options)
    return nil unless defined?(ActionController)

    controller = instance_double(ActionController::Base)

    allow(controller).to receive(:request) do
      request = instance_double(ActionDispatch::Request)
      allow(request).to receive_messages(
        body: StringIO.new(options[:request_body] || build_json_rpc_request("test/method").to_json), headers: options[:headers] || {}, path: options[:path] || "/a2a/rpc"
      )
      request
    end

    allow(controller).to receive(:render) do |options|
      { rendered: true, options: options }
    end

    controller
  end

  # Verification helpers

  # Verify that a mock was called with specific arguments
  def verify_mock_called(mock, method, *expected_args, **expected_kwargs)
    expect(mock).to have_received(method).with(*expected_args, **expected_kwargs)
  end

  # Verify that a mock was called a specific number of times
  def verify_mock_call_count(mock, method, count)
    expect(mock).to have_received(method).exactly(count).times
  end

  # Verify that multiple mocks were called in order
  def verify_call_order(*mock_method_pairs)
    mock_method_pairs.each_cons(2) do |(first_mock, first_method), (second_mock, second_method)|
      expect(first_mock).to have_received(first_method).ordered
      expect(second_mock).to have_received(second_method).ordered
    end
  end
end

RSpec.configure do |config|
  config.include A2ATestDoubles
end
