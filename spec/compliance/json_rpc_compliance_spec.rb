# frozen_string_literal: true

##
# JSON-RPC 2.0 Compliance Test Suite
#
# This test suite validates complete compliance with the JSON-RPC 2.0 specification
# as required by the A2A protocol.
#
# @see https://www.jsonrpc.org/specification JSON-RPC 2.0 Specification
#
RSpec.describe "JSON-RPC 2.0 Compliance", :compliance do
  let(:parser) { A2A::Protocol::JsonRpc }

  describe "Request Parsing" do
    context "valid requests" do
      it "parses simple requests with all required fields" do
        request_json = {
          jsonrpc: "2.0",
          method: "subtract",
          params: [42, 23],
          id: 1
        }.to_json

        request = parser.parse_request(request_json)

        expect(request).to be_a(A2A::Protocol::Request)
        expect(request.jsonrpc).to eq("2.0")
        expect(request.method).to eq("subtract")
        expect(request.params).to eq([42, 23])
        expect(request.id).to eq(1)
      end

      it "parses requests with named parameters" do
        request_json = {
          jsonrpc: "2.0",
          method: "subtract",
          params: { subtrahend: 23, minuend: 42 },
          id: 3
        }.to_json

        request = parser.parse_request(request_json)

        expect(request.params).to eq({ "subtrahend" => 23, "minuend" => 42 })
      end

      it "parses notifications (requests without id)" do
        request_json = {
          jsonrpc: "2.0",
          method: "update",
          params: [1, 2, 3, 4, 5]
        }.to_json

        request = parser.parse_request(request_json)

        expect(request.notification?).to be true
        expect(request.id).to be_nil
      end

      it "parses requests without parameters" do
        request_json = {
          jsonrpc: "2.0",
          method: "foobar",
          id: "1"
        }.to_json

        request = parser.parse_request(request_json)

        expect(request.params).to eq({})
        expect(request.id).to eq("1")
      end

      it "accepts string IDs" do
        request_json = {
          jsonrpc: "2.0",
          method: "test",
          id: "string-id-123"
        }.to_json

        request = parser.parse_request(request_json)
        expect(request.id).to eq("string-id-123")
      end

      it "accepts numeric IDs" do
        request_json = {
          jsonrpc: "2.0",
          method: "test",
          id: 42
        }.to_json

        request = parser.parse_request(request_json)
        expect(request.id).to eq(42)
      end

      it "accepts null ID for notifications" do
        request_json = {
          jsonrpc: "2.0",
          method: "notification",
          id: nil
        }.to_json

        request = parser.parse_request(request_json)
        expect(request.id).to be_nil
        expect(request.notification?).to be true
      end
    end

    context "batch requests" do
      it "parses valid batch requests" do
        batch_json = [
          { jsonrpc: "2.0", method: "sum", params: [1, 2, 4], id: "1" },
          { jsonrpc: "2.0", method: "notify_hello", params: [7] },
          { jsonrpc: "2.0", method: "subtract", params: [42, 23], id: "2" },
          { jsonrpc: "2.0", method: "get_data", id: "9" }
        ].to_json

        requests = parser.parse_request(batch_json)

        expect(requests).to be_an(Array)
        expect(requests.length).to eq(4)

        expect(requests[0].method).to eq("sum")
        expect(requests[0].id).to eq("1")

        expect(requests[1].method).to eq("notify_hello")
        expect(requests[1].notification?).to be true

        expect(requests[2].method).to eq("subtract")
        expect(requests[2].id).to eq("2")

        expect(requests[3].method).to eq("get_data")
        expect(requests[3].id).to eq("9")
      end

      it "rejects empty batch requests" do
        expect do
          parser.parse_request("[]")
        end.to raise_error(A2A::Errors::InvalidRequest, /empty batch/i)
      end
    end

    context "invalid requests" do
      it "rejects requests with wrong JSON-RPC version" do
        request_json = {
          jsonrpc: "1.0",
          method: "test",
          id: 1
        }.to_json

        expect do
          parser.parse_request(request_json)
        end.to raise_error(A2A::Errors::InvalidRequest)
      end

      it "rejects requests without jsonrpc field" do
        request_json = {
          method: "test",
          id: 1
        }.to_json

        expect do
          parser.parse_request(request_json)
        end.to raise_error(A2A::Errors::InvalidRequest)
      end

      it "rejects requests without method field" do
        request_json = {
          jsonrpc: "2.0",
          id: 1
        }.to_json

        expect do
          parser.parse_request(request_json)
        end.to raise_error(A2A::Errors::InvalidRequest)
      end

      it "rejects requests with non-string method" do
        request_json = {
          jsonrpc: "2.0",
          method: 123,
          id: 1
        }.to_json

        expect do
          parser.parse_request(request_json)
        end.to raise_error(A2A::Errors::InvalidRequest)
      end

      it "rejects requests with invalid params type" do
        request_json = {
          jsonrpc: "2.0",
          method: "test",
          params: "invalid",
          id: 1
        }.to_json

        expect do
          parser.parse_request(request_json)
        end.to raise_error(A2A::Errors::InvalidRequest)
      end

      it "rejects invalid JSON" do
        expect do
          parser.parse_request('{"jsonrpc": "2.0", "method": "test", "id": 1,}') # trailing comma
        end.to raise_error(A2A::Errors::ParseError)
      end

      it "rejects non-JSON input" do
        expect do
          parser.parse_request("not json at all")
        end.to raise_error(A2A::Errors::ParseError)
      end
    end
  end

  describe "Response Building" do
    context "success responses" do
      it "builds responses with results" do
        response = parser.build_response(result: "success", id: 1)

        expect(response).to be_valid_json_rpc_response
        expect(response[:jsonrpc]).to eq("2.0")
        expect(response[:result]).to eq("success")
        expect(response[:id]).to eq(1)
        expect(response).not_to have_key(:error)
      end

      it "builds responses with complex result objects" do
        result = { data: [1, 2, 3], status: "ok", metadata: { count: 3 } }
        response = parser.build_response(result: result, id: "test-id")

        expect(response[:result]).to eq(result)
        expect(response[:id]).to eq("test-id")
      end

      it "builds responses with null results" do
        response = parser.build_response(result: nil, id: 1)

        expect(response[:result]).to be_nil
        expect(response).to have_key(:result)
      end
    end

    context "error responses" do
      it "builds error responses with all fields" do
        error = { code: -32_601, message: "Method not found", data: "Additional info" }
        response = parser.build_response(error: error, id: 1)

        expect(response).to be_valid_json_rpc_response
        expect(response[:jsonrpc]).to eq("2.0")
        expect(response[:error]).to eq(error)
        expect(response[:id]).to eq(1)
        expect(response).not_to have_key(:result)
      end

      it "builds error responses without data field" do
        error = { code: -32_600, message: "Invalid Request" }
        response = parser.build_response(error: error, id: nil)

        expect(response[:error]).to eq(error)
        expect(response[:id]).to be_nil
      end

      it "builds error responses using build_error_response helper" do
        response = parser.build_error_response(
          code: -32_001,
          message: "Task not found",
          data: { taskId: "123" },
          id: 1
        )

        expect(response).to have_json_rpc_error(-32_001)
        expect(response[:error][:message]).to eq("Task not found")
        expect(response[:error][:data]).to eq({ taskId: "123" })
      end
    end

    context "batch responses" do
      it "builds batch responses" do
        responses = [
          { jsonrpc: "2.0", result: 7, id: "1" },
          { jsonrpc: "2.0", result: 19, id: "2" },
          { jsonrpc: "2.0", error: { code: -32_601, message: "Method not found" }, id: "5" }
        ]

        batch_response = parser.build_batch_response(responses)

        expect(batch_response).to be_an(Array)
        expect(batch_response.length).to eq(3)
        batch_response.each { |resp| expect(resp).to be_valid_json_rpc_response }
      end

      it "filters out notification responses from batch" do
        responses = [
          { jsonrpc: "2.0", result: 7, id: "1" },
          { jsonrpc: "2.0", result: nil, id: nil }, # notification response
          { jsonrpc: "2.0", result: 19, id: "2" }
        ]

        batch_response = parser.build_batch_response(responses)

        expect(batch_response.length).to eq(2)
        expect(batch_response.pluck(:id)).to eq(%w[1 2])
      end
    end

    context "validation" do
      it "rejects responses with both result and error" do
        expect do
          parser.build_response(result: "success", error: { code: -1, message: "error" }, id: 1)
        end.to raise_error(ArgumentError, /cannot specify both/i)
      end

      it "rejects responses with neither result nor error" do
        expect do
          parser.build_response(id: 1)
        end.to raise_error(ArgumentError, /must specify either/i)
      end
    end
  end

  describe "Error Code Compliance" do
    context "standard JSON-RPC error codes" do
      it "defines parse error code" do
        expect(parser::PARSE_ERROR).to eq(-32_700)
      end

      it "defines invalid request code" do
        expect(parser::INVALID_REQUEST).to eq(-32_600)
      end

      it "defines method not found code" do
        expect(parser::METHOD_NOT_FOUND).to eq(-32_601)
      end

      it "defines invalid params code" do
        expect(parser::INVALID_PARAMS).to eq(-32_602)
      end

      it "defines internal error code" do
        expect(parser::INTERNAL_ERROR).to eq(-32_603)
      end
    end

    context "A2A-specific error codes" do
      it "defines task not found code" do
        expect(parser::TASK_NOT_FOUND).to eq(-32_001)
      end

      it "defines task not cancelable code" do
        expect(parser::TASK_NOT_CANCELABLE).to eq(-32_002)
      end

      it "defines authentication required code" do
        expect(parser::AUTHENTICATION_REQUIRED).to eq(-32_004)
      end

      it "uses A2A error codes in range -32001 to -32010" do
        a2a_codes = [
          parser::TASK_NOT_FOUND,
          parser::TASK_NOT_CANCELABLE,
          parser::INVALID_TASK_STATE,
          parser::AUTHENTICATION_REQUIRED,
          parser::AUTHORIZATION_FAILED,
          parser::RATE_LIMIT_EXCEEDED,
          parser::AGENT_UNAVAILABLE,
          parser::PROTOCOL_VERSION_MISMATCH,
          parser::CAPABILITY_NOT_SUPPORTED,
          parser::RESOURCE_EXHAUSTED
        ]

        a2a_codes.each do |code|
          expect(code).to be_between(-32_010, -32_001)
        end
      end
    end
  end

  describe "Request Validation" do
    it "validates correct request format" do
      valid_request = {
        "jsonrpc" => "2.0",
        "method" => "test",
        "params" => { "key" => "value" },
        "id" => 1
      }

      expect(parser.valid_request?(valid_request)).to be true
    end

    it "rejects invalid request formats" do
      invalid_requests = [
        nil,
        "not a hash",
        {},
        { "jsonrpc" => "1.0", "method" => "test", "id" => 1 },
        { "jsonrpc" => "2.0", "id" => 1 }, # missing method
        { "jsonrpc" => "2.0", "method" => 123, "id" => 1 }, # invalid method type
        { "jsonrpc" => "2.0", "method" => "test", "params" => "invalid", "id" => 1 }
      ]

      invalid_requests.each do |request|
        expect(parser.valid_request?(request)).to be false
      end
    end
  end

  describe "Edge Cases and Robustness" do
    it "handles very large request IDs" do
      large_id = (2**53) - 1 # Maximum safe integer in JSON
      request_json = {
        jsonrpc: "2.0",
        method: "test",
        id: large_id
      }.to_json

      request = parser.parse_request(request_json)
      expect(request.id).to eq(large_id)
    end

    it "handles Unicode in method names and parameters" do
      request_json = {
        jsonrpc: "2.0",
        method: "测试方法",
        params: { "参数" => "值", "emoji" => "🚀" },
        id: 1
      }.to_json

      request = parser.parse_request(request_json)
      expect(request.method).to eq("测试方法")
      expect(request.params["参数"]).to eq("值")
      expect(request.params["emoji"]).to eq("🚀")
    end

    it "handles deeply nested parameter structures" do
      deep_params = {
        level1: {
          level2: {
            level3: {
              level4: {
                value: "deep"
              }
            }
          }
        }
      }

      request_json = {
        jsonrpc: "2.0",
        method: "deep_test",
        params: deep_params,
        id: 1
      }.to_json

      request = parser.parse_request(request_json)
      expect(request.params.dig("level1", "level2", "level3", "level4", "value")).to eq("deep")
    end

    it "handles empty arrays and objects in parameters" do
      request_json = {
        jsonrpc: "2.0",
        method: "test",
        params: {
          empty_array: [],
          empty_object: {},
          nested: {
            also_empty: []
          }
        },
        id: 1
      }.to_json

      request = parser.parse_request(request_json)
      expect(request.params["empty_array"]).to eq([])
      expect(request.params["empty_object"]).to eq({})
      expect(request.params.dig("nested", "also_empty")).to eq([])
    end
  end

  describe "Performance and Memory" do
    it "handles large batch requests efficiently" do
      large_batch = (1..1000).map do |i|
        {
          jsonrpc: "2.0",
          method: "batch_method_#{i}",
          params: { index: i, data: "x" * 100 },
          id: i
        }
      end

      batch_json = large_batch.to_json

      result = measure_time do
        requests = parser.parse_request(batch_json)
        expect(requests.length).to eq(1000)
      end

      # Should parse 1000 requests in reasonable time (< 1 second)
      expect(result[:duration]).to be < 1.0
    end

    it "handles large parameter payloads" do
      large_data = "x" * 100_000 # 100KB string
      request_json = {
        jsonrpc: "2.0",
        method: "large_data",
        params: { data: large_data },
        id: 1
      }.to_json

      result = measure_time do
        request = parser.parse_request(request_json)
        expect(request.params["data"].length).to eq(100_000)
      end

      # Should handle large payloads efficiently
      expect(result[:duration]).to be < 0.5
    end
  end
end
