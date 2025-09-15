# frozen_string_literal: true

require "json"
require "securerandom"

module A2A
  module Client
    ##
    # JSON-RPC request handling functionality
    #
    module JsonRpcHandler
      ##
      # Initialize JSON-RPC handling
      #
      def initialize_json_rpc_handling
        @request_id_counter = 0
        @request_id_mutex = Mutex.new
      end

      ##
      # Send a JSON-RPC request
      #
      # @param request [Hash] The JSON-RPC request
      # @return [Hash] The parsed response
      def send_json_rpc_request(request)
        start_time = Time.now
        response = @connection.post("/", request.to_json, "Content-Type" => "application/json")
        duration = Time.now - start_time

        record_request_performance(duration)
        handle_http_response(response)
      end

      ##
      # Send a streaming JSON-RPC request
      #
      # @param request [Hash] The JSON-RPC request
      # @return [Enumerator] Stream of parsed responses
      def send_streaming_request(request)
        Enumerator.new do |yielder|
          response = @connection.post("/stream", request.to_json) do |req|
            req.headers["Content-Type"] = "application/json"
            req.headers["Accept"] = "text/event-stream"
          end

          raise A2A::Errors::HTTPError, "HTTP #{response.status}: #{response.body}" unless response.success?

          response.body.each_line do |line|
            event = parse_sse_chunk(line.strip)
            yielder << event if event
          end
        end
      end

      ##
      # Handle HTTP response
      #
      # @param response [Faraday::Response] The HTTP response
      # @return [Hash] The parsed JSON-RPC response
      def handle_http_response(response)
        unless response.success?
          case response.status
          when 408
            raise A2A::Errors::TimeoutError, "Request timeout"
          when 400..499
            raise A2A::Errors::HTTPError, "HTTP #{response.status}: #{response.body}"
          when 500..599
            raise A2A::Errors::HTTPError, "HTTP #{response.status}: #{response.body}"
          else
            raise A2A::Errors::HTTPError, "HTTP #{response.status}: #{response.body}"
          end
        end

        begin
          parsed_response = JSON.parse(response.body)
        rescue JSON::ParserError => e
          raise A2A::Errors::ParseError, "Invalid JSON response: #{e.message}"
        end

        if parsed_response["error"]
          error_code = parsed_response["error"]["code"]
          error_message = parsed_response["error"]["message"]
          raise A2A::Errors::A2AError.new(error_message, error_code)
        end

        parsed_response
      end

      ##
      # Parse Server-Sent Events chunk
      #
      # @param chunk [String] The SSE chunk
      # @return [Hash, nil] The parsed event or nil
      def parse_sse_chunk(chunk)
        return nil if chunk.empty? || chunk.start_with?(":")

        return unless chunk.start_with?("data: ")

        data = chunk[6..] # Remove "data: " prefix
        return nil if data == "[DONE]"

        begin
          JSON.parse(data)
        rescue JSON::ParserError
          nil
        end
      end

      ##
      # Build a JSON-RPC request
      #
      # @param method [String] The method name
      # @param params [Hash] The parameters
      # @return [Hash] The JSON-RPC request
      def build_json_rpc_request(method, params = {})
        {
          jsonrpc: "2.0",
          method: method,
          params: params,
          id: next_request_id
        }
      end

      ##
      # Generate the next request ID
      #
      # @return [String] The request ID
      def next_request_id
        @request_id_mutex.synchronize do
          @request_id_counter += 1
          "#{SecureRandom.hex(8)}-#{@request_id_counter}"
        end
      end
    end
  end
end
