# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Transport Integration' do
  describe 'HTTP Transport with JSON-RPC' do
    let(:base_url) { 'https://api.example.com' }
    let(:transport) { A2A::Transport::Http.new(base_url) }

    it 'handles complete JSON-RPC request/response cycle' do
      rpc_request = {
        jsonrpc: '2.0',
        method: 'message/send',
        params: {
          message: {
            message_id: 'test-123',
            role: 'user',
            parts: [
              {
                kind: 'text',
                text: 'Hello, agent!'
              }
            ]
          }
        },
        id: 1
      }

      rpc_response = {
        jsonrpc: '2.0',
        result: {
          task: {
            id: 'task-456',
            context_id: 'ctx-789',
            status: {
              state: 'submitted'
            }
          }
        },
        id: 1
      }

      stub_request(:post, base_url)
        .with(
          body: rpc_request.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
        .to_return(
          status: 200,
          body: rpc_response.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      response = transport.json_rpc_request(rpc_request)

      expect(response['jsonrpc']).to eq('2.0')
      expect(response['result']['task']['id']).to eq('task-456')
      expect(response['id']).to eq(1)
    end

    it 'handles error responses correctly' do
      rpc_request = {
        jsonrpc: '2.0',
        method: 'invalid/method',
        id: 1
      }

      error_response = {
        jsonrpc: '2.0',
        error: {
          code: -32601,
          message: 'Method not found'
        },
        id: 1
      }

      stub_request(:post, base_url)
        .with(body: rpc_request.to_json)
        .to_return(
          status: 200,
          body: error_response.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      response = transport.json_rpc_request(rpc_request)

      expect(response['jsonrpc']).to eq('2.0')
      expect(response['error']['code']).to eq(-32601)
      expect(response['error']['message']).to eq('Method not found')
    end
  end

  describe 'SSE Event Processing' do
    let(:url) { 'https://api.example.com/events' }
    let(:sse) { A2A::Transport::SSE.new(url) }

    it 'creates and formats events correctly' do
      event = A2A::Transport::SSEEvent.new(
        type: 'task_status_update',
        data: {
          task_id: 'task-123',
          status: { state: 'completed' }
        },
        id: 'event-456'
      )

      sse_format = event.to_sse_format

      expect(sse_format).to include('event: task_status_update')
      expect(sse_format).to include('id: event-456')
      expect(sse_format).to include('data: {"task_id":"task-123"')
    end

    it 'manages event listeners correctly' do
      received_events = []
      
      sse.on('message') do |event|
        received_events << event
      end

      # Simulate event emission
      test_event = A2A::Transport::SSEEvent.new(
        type: 'message',
        data: { text: 'Hello' }
      )

      sse.send(:emit_event, test_event)

      expect(received_events.size).to eq(1)
      expect(received_events.first.type).to eq('message')
      expect(received_events.first.data[:text]).to eq('Hello')
    end
  end

  describe 'gRPC Transport (when available)' do
    context 'when gRPC is not available' do
      it 'provides helpful error message' do
        expect {
          A2A::Transport::Grpc.new('localhost:50051')
        }.to raise_error(A2A::Errors::TransportError, /gRPC is not available/)
      end
    end
  end
end