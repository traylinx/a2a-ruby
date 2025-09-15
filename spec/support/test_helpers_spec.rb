# frozen_string_literal: true

RSpec.describe "A2A Test Helpers and Matchers" do
  describe "Custom Matchers" do
    describe "be_valid_json_rpc_request" do
      it "validates correct JSON-RPC 2.0 requests" do
        request = build_json_rpc_request("test/method", { key: "value" })
        expect(request).to be_valid_json_rpc_request
      end

      it "rejects invalid requests" do
        invalid_request = { jsonrpc: "1.0", method: "test" }
        expect(invalid_request).not_to be_valid_json_rpc_request
      end
    end

    describe "be_valid_json_rpc_response" do
      it "validates success responses" do
        response = {
          jsonrpc: "2.0",
          result: { message: "success" },
          id: 1
        }
        expect(response).to be_valid_json_rpc_response
      end

      it "validates error responses" do
        response = {
          jsonrpc: "2.0",
          error: { code: -32001, message: "Task not found" },
          id: 1
        }
        expect(response).to be_valid_json_rpc_response
      end
    end

    describe "be_valid_agent_card" do
      it "validates complete agent cards" do
        card = build_agent_card
        expect(card).to be_valid_agent_card
      end

      it "validates generated full agent cards" do
        card = generate_full_agent_card
        expect(card).to be_valid_agent_card
      end
    end

    describe "be_valid_a2a_message" do
      it "validates A2A messages" do
        message = build_message
        expect(message).to be_valid_a2a_message
      end

      it "validates complex messages" do
        message = generate_complex_message
        expect(message).to be_valid_a2a_message
      end
    end

    describe "be_valid_a2a_task" do
      it "validates A2A tasks" do
        task = build_task
        expect(task).to be_valid_a2a_task
      end

      it "validates comprehensive tasks" do
        task = generate_comprehensive_task
        expect(task).to be_valid_a2a_task
      end
    end

    describe "have_json_rpc_error" do
      it "matches specific error codes" do
        error_response = create_json_rpc_error(
          code: A2A::Protocol::JsonRpc::TASK_NOT_FOUND,
          message: "Task not found"
        )
        expect(error_response).to have_json_rpc_error(A2A::Protocol::JsonRpc::TASK_NOT_FOUND)
      end
    end

    describe "have_a2a_error" do
      it "matches A2A-specific error codes" do
        error_response = create_json_rpc_error(
          code: A2A::Protocol::JsonRpc::TASK_NOT_FOUND,
          message: "Task not found"
        )
        expect(error_response).to have_a2a_error(A2A::Protocol::JsonRpc::TASK_NOT_FOUND)
      end
    end

    describe "be_streaming_response" do
      it "identifies streaming responses" do
        stream = create_test_sse_stream(build_message)
        expect(stream).to be_streaming_response
      end
    end

    describe "be_valid_sse_event" do
      it "validates Server-Sent Events format" do
        event = format_sse_event({ message: "test" })
        expect(event).to be_valid_sse_event
      end
    end
  end

  describe "Test Helpers" do
    describe "JSON-RPC helpers" do
      it "builds valid JSON-RPC requests" do
        request = build_json_rpc_request("test/method", { param: "value" }, 123)
        
        expect(request[:jsonrpc]).to eq("2.0")
        expect(request[:method]).to eq("test/method")
        expect(request[:params]).to eq({ param: "value" })
        expect(request[:id]).to eq(123)
      end

      it "builds batch requests" do
        batch = build_json_rpc_batch(
          { method: "method1", params: { a: 1 } },
          { method: "method2", params: { b: 2 } }
        )
        
        expect(batch).to be_an(Array)
        expect(batch.length).to eq(2)
        expect(batch[0][:method]).to eq("method1")
        expect(batch[1][:method]).to eq("method2")
      end
    end

    describe "Data generators" do
      it "generates test UUIDs" do
        uuid = test_uuid
        expect(uuid).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
      end

      it "generates test timestamps" do
        timestamp = test_timestamp
        expect(timestamp).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      end

      it "generates test auth tokens" do
        token = test_auth_token
        expect(token).to start_with("test_token_")
      end
    end

    describe "Protocol validation helpers" do
      it "validates JSON-RPC requests" do
        request = build_json_rpc_request("test/method")
        expect { validate_json_rpc_request(request) }.not_to raise_error
      end

      it "validates agent cards" do
        card = build_agent_card
        expect { validate_agent_card(card) }.not_to raise_error
      end
    end

    describe "Streaming helpers" do
      it "creates SSE streams" do
        events = [
          build_message(text: "First message"),
          build_message(text: "Second message")
        ]
        
        stream = create_test_sse_stream(*events)
        expect(stream).to be_streaming_response
        
        collected_events = stream.to_a
        expect(collected_events.length).to eq(2)
      end

      it "formats SSE events" do
        data = { message: "test", id: 123 }
        sse_event = format_sse_event(data, event_type: "message", id: "event-1")
        
        expect(sse_event).to include("id: event-1")
        expect(sse_event).to include("event: message")
        expect(sse_event).to include("data: #{data.to_json}")
      end

      it "parses SSE events" do
        sse_string = "id: test-1\nevent: message\ndata: {\"text\":\"hello\"}\n\n"
        parsed = parse_sse_event(sse_string)
        
        expect(parsed[:id]).to eq("test-1")
        expect(parsed[:event]).to eq("message")
        expect(parsed[:data]).to eq({ "text" => "hello" })
      end
    end

    describe "Performance helpers" do
      it "measures execution time" do
        result = measure_time do
          sleep(0.01) # 10ms
          "test_result"
        end
        
        expect(result[:result]).to eq("test_result")
        expect(result[:duration]).to be > 0.009
        expect(result[:duration_ms]).to be > 9
      end

      it "runs concurrent operations" do
        results = run_concurrently(thread_count: 5) do |thread_id|
          "result_#{thread_id}"
        end
        
        expect(results.length).to eq(5)
        expect(results).to all(start_with("result_"))
      end
    end

    describe "Authentication helpers" do
      it "creates OAuth2 credentials" do
        creds = create_oauth2_credentials
        
        expect(creds).to have_key(:client_id)
        expect(creds).to have_key(:client_secret)
        expect(creds).to have_key(:token_url)
      end

      it "creates JWT tokens" do
        token = create_jwt_token(payload: { user: "test" })
        
        expect(token).to be_a(String)
        expect(token.split(".").length).to eq(3) # header.payload.signature
      end
    end

    describe "Environment helpers" do
      it "temporarily sets environment variables" do
        original_value = ENV["TEST_VAR"]
        
        with_env("TEST_VAR" => "test_value") do
          expect(ENV["TEST_VAR"]).to eq("test_value")
        end
        
        expect(ENV["TEST_VAR"]).to eq(original_value)
      end
    end
  end

  describe "Test Doubles" do
    describe "mock_a2a_client" do
      it "creates a functional mock client" do
        client = mock_a2a_client
        
        message = build_message
        response = client.send_message(message)
        
        expect(response).to be_a(Hash)
        expect(response[:role]).to eq("agent")
      end

      it "supports streaming responses" do
        client = mock_a2a_client(streaming: true)
        
        message = build_message
        response = client.send_message(message, streaming: true)
        
        expect(response).to be_streaming_response
      end

      it "supports custom responses" do
        custom_response = build_message(text: "Custom response")
        client = mock_a2a_client(responses: { send_message: custom_response })
        
        response = client.send_message(build_message)
        expect(response[:parts].first[:text]).to eq("Custom response")
      end
    end

    describe "mock_task_manager" do
      it "creates a functional task manager mock" do
        task_manager = mock_task_manager
        
        task = task_manager.create_task(type: "test")
        expect(task).to be_valid_a2a_task
        
        retrieved_task = task_manager.get_task(task[:id])
        expect(retrieved_task[:id]).to eq(task[:id])
      end
    end

    describe "mock_storage_backend" do
      it "provides in-memory storage simulation" do
        storage = mock_storage_backend
        
        task = build_task
        storage.save_task(task)
        
        retrieved = storage.get_task(task[:id])
        expect(retrieved[:id]).to eq(task[:id])
      end
    end
  end

  describe "Fixture Generators" do
    describe "generate_full_agent_card" do
      it "creates comprehensive agent cards" do
        card = generate_full_agent_card
        
        expect(card).to be_valid_agent_card
        expect(card[:skills]).not_to be_empty
        expect(card[:additionalInterfaces]).not_to be_empty
        expect(card[:securitySchemes]).not_to be_empty
      end
    end

    describe "generate_complex_message" do
      it "creates messages with multiple part types" do
        message = generate_complex_message
        
        expect(message).to be_valid_a2a_message
        expect(message[:parts].length).to be > 1
        
        part_kinds = message[:parts].map { |p| p[:kind] }
        expect(part_kinds).to include("text", "file", "data")
      end
    end

    describe "generate_comprehensive_task" do
      it "creates tasks with full lifecycle data" do
        task = generate_comprehensive_task
        
        expect(task).to be_valid_a2a_task
        expect(task[:artifacts]).not_to be_empty
        expect(task[:history]).not_to be_empty
        expect(task[:status][:state]).to eq("completed")
      end
    end

    describe "generate_task_status_events" do
      it "creates a sequence of status updates" do
        task_id = test_uuid
        context_id = test_uuid
        
        events = generate_task_status_events(
          task_id: task_id,
          context_id: context_id
        )
        
        expect(events.length).to eq(3)
        expect(events.map { |e| e[:status][:state] }).to eq(["submitted", "working", "completed"])
        events.each { |event| expect(event).to be_valid_task_status_update_event }
      end
    end
  end

  describe "Integration" do
    it "works together for comprehensive testing" do
      # Create a mock client with custom agent card
      agent_card = generate_full_agent_card(name: "Integration Test Agent")
      client = mock_a2a_client(agent_card: agent_card)
      
      # Send a complex message
      message = generate_complex_message
      validate_a2a_message(message)
      
      # Get response (mocked)
      response = client.send_message(message)
      expect(response).to be_a(Hash)
      
      # Create and validate a task
      task = generate_comprehensive_task
      validate_a2a_task(task)
      
      # Test streaming
      stream = create_test_sse_stream(
        build_task_status_update(
          task_id: task[:id],
          context_id: task[:contextId],
          state: "working"
        )
      )
      expect(stream).to be_streaming_response
      
      # Verify everything works together
      expect(agent_card).to be_valid_agent_card
      expect(message).to be_valid_a2a_message
      expect(task).to be_valid_a2a_task
    end
  end
end