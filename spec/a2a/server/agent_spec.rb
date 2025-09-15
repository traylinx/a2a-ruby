# frozen_string_literal: true

require "spec_helper"

RSpec.describe A2A::Server::Agent do
  let(:test_agent_class) do
    Class.new do
      include A2A::Server::Agent

      a2a_method "echo" do |params|
        { message: params["message"] }
      end

      a2a_method "greet" do |params, _context|
        name = params["name"] || "World"
        { greeting: "Hello, #{name}!" }
      end

      a2a_capability "echo_capability" do
        method :echo
        description "Echo back the input message"
        input_schema type: "object", properties: { message: { type: "string" } }
        output_schema type: "object", properties: { message: { type: "string" } }
      end
    end
  end

  let(:agent) { test_agent_class.new }

  describe "class methods" do
    it "registers A2A methods" do
      expect(test_agent_class.a2a_method_registered?("echo")).to be true
      expect(test_agent_class.a2a_method_registered?("greet")).to be true
      expect(test_agent_class.a2a_method_registered?("nonexistent")).to be false
    end

    it "stores method definitions" do
      method_def = test_agent_class.a2a_method_definition("echo")
      expect(method_def).to be_a(Hash)
      expect(method_def[:handler]).to be_a(Proc)
      expect(method_def[:streaming]).to be false
      expect(method_def[:async]).to be false
    end

    it "registers capabilities" do
      capabilities = test_agent_class.a2a_capability_registry.all
      expect(capabilities.size).to be >= 1

      echo_capability = capabilities.find { |c| c.name == "echo_capability" }
      expect(echo_capability).not_to be_nil
      expect(echo_capability.method).to eq("echo")
    end
  end

  describe "#handle_a2a_request" do
    let(:echo_request) do
      A2A::Protocol::Request.new(
        jsonrpc: "2.0",
        method: "echo",
        params: { "message" => "Hello, World!" },
        id: 1
      )
    end

    let(:greet_request) do
      A2A::Protocol::Request.new(
        jsonrpc: "2.0",
        method: "greet",
        params: { "name" => "Alice" },
        id: 2
      )
    end

    let(:unknown_request) do
      A2A::Protocol::Request.new(
        jsonrpc: "2.0",
        method: "unknown_method",
        params: {},
        id: 3
      )
    end

    it "handles echo method correctly" do
      response = agent.handle_a2a_request(echo_request)

      expect(response).to be_a(Hash)
      expect(response[:jsonrpc]).to eq("2.0")
      expect(response[:id]).to eq(1)
      expect(response[:result]).to eq({ message: "Hello, World!" })
    end

    it "handles greet method with context" do
      response = agent.handle_a2a_request(greet_request)

      expect(response).to be_a(Hash)
      expect(response[:jsonrpc]).to eq("2.0")
      expect(response[:id]).to eq(2)
      expect(response[:result]).to eq({ greeting: "Hello, Alice!" })
    end

    it "returns error for unknown method" do
      response = agent.handle_a2a_request(unknown_request)

      expect(response).to be_a(Hash)
      expect(response[:jsonrpc]).to eq("2.0")
      expect(response[:id]).to eq(3)
      expect(response[:error]).to be_a(Hash)
      expect(response[:error][:code]).to eq(-32_601) # Method not found
    end

    it "handles notification requests (no response)" do
      notification = A2A::Protocol::Request.new(
        jsonrpc: "2.0",
        method: "echo",
        params: { "message" => "Hello!" }
        # No ID = notification
      )

      response = agent.handle_a2a_request(notification)
      expect(response).to be_nil
    end
  end
end
