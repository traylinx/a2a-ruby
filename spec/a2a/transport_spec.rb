# frozen_string_literal: true

require "spec_helper"

RSpec.describe A2A::Transport do
  describe A2A::Transport::Http do
    let(:base_url) { "https://api.example.com" }
    let(:config) { {} }
    let(:transport) { described_class.new(base_url, config) }

    describe "#initialize" do
      it "sets base URL and configuration" do
        expect(transport.base_url).to eq(base_url)
        expect(transport.config).to include(:timeout, :ssl_verify)
      end

      it "builds Faraday connection" do
        expect(transport.connection).to be_a(Faraday::Connection)
      end
    end

    describe "#get" do
      it "sends GET request" do
        stub_request(:get, "#{base_url}/test")
          .to_return(status: 200, body: '{"success": true}')

        response = transport.get("/test")
        expect(response.status).to eq(200)
      end
    end

    describe "#post" do
      it "sends POST request with JSON body" do
        stub_request(:post, "#{base_url}/test")
          .with(body: '{"key":"value"}')
          .to_return(status: 201, body: '{"created": true}')

        response = transport.post("/test", body: { key: "value" })
        expect(response.status).to eq(201)
      end
    end

    describe "#json_rpc_request" do
      it "sends JSON-RPC formatted request" do
        rpc_request = {
          jsonrpc: "2.0",
          method: "test_method",
          params: { key: "value" },
          id: 1
        }

        stub_request(:post, base_url)
          .with(
            body: rpc_request.to_json,
            headers: { "Content-Type" => "application/json" }
          )
          .to_return(
            status: 200,
            body: { jsonrpc: "2.0", result: "success", id: 1 }.to_json
          )

        response = transport.json_rpc_request(rpc_request)
        expect(response["result"]).to eq("success")
      end
    end

    describe "error handling" do
      it "raises HTTPError on 4xx status" do
        stub_request(:get, "#{base_url}/test")
          .to_return(status: 404, body: "Not Found")

        expect do
          transport.get("/test")
        end.to raise_error(A2A::Errors::HTTPError) do |error|
          expect(error.status_code).to eq(404)
        end
      end

      it "raises TimeoutError on timeout" do
        stub_request(:get, "#{base_url}/test").to_timeout

        expect do
          transport.get("/test")
        end.to raise_error(A2A::Errors::TimeoutError)
      end
    end

    describe "metrics" do
      it "tracks request metrics" do
        stub_request(:get, "#{base_url}/test")
          .to_return(status: 200, body: "OK")

        transport.get("/test")
        metrics = transport.metrics

        expect(metrics["get_requests"]).to eq(1)
        expect(metrics["total_requests"]).to eq(1)
        expect(metrics["get_200"]).to eq(1)
      end
    end
  end

  describe A2A::Transport::SSE do
    let(:url) { "https://api.example.com/events" }
    let(:config) { {} }
    let(:sse) { described_class.new(url, config) }

    describe "#initialize" do
      it "sets URL and configuration" do
        expect(sse.url).to eq(url)
        expect(sse.config).to include(:heartbeat_interval, :auto_reconnect)
      end

      it "initializes connection state as disconnected" do
        expect(sse.connection_state).to eq(:disconnected)
      end
    end

    describe "event listeners" do
      it "adds event listeners" do
        handler = proc { |event| puts event.data }
        sse.on("message", &handler)

        expect(sse.instance_variable_get(:@event_listeners)["message"]).to include(handler)
      end

      it "removes event listeners" do
        handler = proc { |event| puts event.data }
        sse.on("message", &handler)
        sse.off("message", handler)

        expect(sse.instance_variable_get(:@event_listeners)["message"]).not_to include(handler)
      end
    end

    describe "#connected?" do
      it "returns false when disconnected" do
        expect(sse.connected?).to be false
      end
    end

    describe "event buffering" do
      it "buffers events" do
        event = A2A::Transport::SSEEvent.new(type: "test", data: { message: "hello" })
        sse.send(:buffer_event, event)

        expect(sse.buffered_events).to include(event)
      end

      it "clears buffer" do
        event = A2A::Transport::SSEEvent.new(type: "test", data: { message: "hello" })
        sse.send(:buffer_event, event)
        sse.clear_buffer!

        expect(sse.buffered_events).to be_empty
      end
    end
  end

  describe A2A::Transport::SSEEvent do
    let(:event) { described_class.new(type: "message", data: { text: "hello" }, id: "123") }

    describe "#initialize" do
      it "sets event properties" do
        expect(event.type).to eq("message")
        expect(event.data).to eq({ text: "hello" })
        expect(event.id).to eq("123")
      end
    end

    describe "#to_sse_format" do
      it "formats event as SSE string" do
        sse_string = event.to_sse_format

        expect(sse_string).to include("id: 123")
        expect(sse_string).to include('data: {"text":"hello"}')
      end
    end

    describe "#type?" do
      it "checks event type" do
        expect(event.type?("message")).to be true
        expect(event.type?("error")).to be false
      end
    end

    describe "#has_data?" do
      it "checks if event has data" do
        expect(event.has_data?).to be true

        empty_event = described_class.new(type: "heartbeat")
        expect(empty_event.has_data?).to be false
      end
    end
  end

  describe A2A::Transport::Grpc do
    let(:endpoint) { "localhost:50051" }
    let(:config) { {} }

    context "when gRPC is not available" do
      before do
        stub_const("A2A::Transport::Grpc::GRPC_AVAILABLE", false)
      end

      it "raises error on initialization" do
        expect do
          described_class.new(endpoint, config)
        end.to raise_error(A2A::Errors::TransportError, /gRPC is not available/)
      end
    end

    context "when gRPC is available" do
      before do
        stub_const("A2A::Transport::Grpc::GRPC_AVAILABLE", true)

        # Mock GRPC constants and classes
        grpc_core = Module.new do
          const_set(:StatusCodes, Module.new do
            const_set(:NOT_FOUND, 5)
            const_set(:CANCELLED, 1)
            const_set(:INVALID_ARGUMENT, 3)
            const_set(:DEADLINE_EXCEEDED, 4)
            const_set(:PERMISSION_DENIED, 7)
            const_set(:RESOURCE_EXHAUSTED, 8)
            const_set(:UNIMPLEMENTED, 12)
            const_set(:UNAVAILABLE, 14)
            const_set(:UNAUTHENTICATED, 16)
          end)
          const_set(:ChannelCredentials, Class.new do
            def self.new(*_args)
              :mock_credentials
            end
          end)
        end

        grpc_module = Module.new do
          const_set(:Core, grpc_core)
        end

        stub_const("::GRPC", grpc_module)
      end

      let(:transport) { described_class.new(endpoint, config) }

      describe "#initialize" do
        it "sets endpoint and configuration" do
          expect(transport.endpoint).to eq(endpoint)
          expect(transport.config).to include(:timeout, :use_tls)
        end
      end

      describe "#connected?" do
        it "returns false when not connected" do
          expect(transport.connected?).to be false
        end
      end

      describe "error mapping" do
        it "maps gRPC errors to A2A errors" do
          grpc_error = double("GRPC::BadStatus",
                              code: GRPC::Core::StatusCodes::NOT_FOUND,
                              details: "Task not found")

          mapped_error = transport.send(:map_grpc_error, grpc_error)
          expect(mapped_error).to be_a(A2A::Errors::TaskNotFound)
        end
      end
    end
  end
end
