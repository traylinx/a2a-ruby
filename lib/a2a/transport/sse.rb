# frozen_string_literal: true

require "json"
require "concurrent"

module A2A
  module Transport
    ##
    # Server-Sent Events (SSE) transport implementation
    # Provides streaming responses with event parsing, connection management, and heartbeat support
    #
    class SSE
      # SSE event types
      EVENT_TYPES = %w[
        message
        error
        heartbeat
        task_status_update
        task_artifact_update
        connection_established
        connection_closed
      ].freeze

      # Default configuration values
      DEFAULT_HEARTBEAT_INTERVAL = 30
      DEFAULT_RECONNECT_DELAY = 3000
      DEFAULT_MAX_RECONNECT_ATTEMPTS = 10
      DEFAULT_BUFFER_SIZE = 1024 * 8 # 8KB
      DEFAULT_TIMEOUT = 60

      attr_reader :url, :config, :connection_state, :event_buffer, :last_event_id

      ##
      # Initialize SSE transport
      #
      # @param url [String] SSE endpoint URL
      # @param config [Hash] Configuration options
      # @option config [Integer] :heartbeat_interval (30) Heartbeat interval in seconds
      # @option config [Integer] :reconnect_delay (3000) Reconnection delay in milliseconds
      # @option config [Integer] :max_reconnect_attempts (10) Maximum reconnection attempts
      # @option config [Integer] :buffer_size (8192) Event buffer size in bytes
      # @option config [Integer] :timeout (60) Connection timeout in seconds
      # @option config [Hash] :headers ({}) Default headers
      # @option config [Boolean] :auto_reconnect (true) Enable automatic reconnection
      # @option config [String] :last_event_id Last received event ID for replay
      #
      def initialize(url, config = {})
        @url = url
        @config = default_config.merge(config)
        @connection_state = :disconnected
        @event_buffer = Concurrent::Array.new
        @last_event_id = @config[:last_event_id]
        @reconnect_attempts = 0
        @heartbeat_timer = nil
        @event_listeners = Concurrent::Hash.new { |h, k| h[k] = [] }
        @mutex = Mutex.new
      end

      ##
      # Connect to SSE endpoint and start streaming
      #
      # @param headers [Hash] Additional headers
      # @yield [event] Block to handle incoming events
      # @yieldparam event [SSEEvent] Received SSE event
      # @return [Enumerator] Event stream enumerator
      #
      def connect(headers: {}, &block)
        @mutex.synchronize do
          return if @connection_state == :connected

          @connection_state = :connecting
          @reconnect_attempts = 0
        end

        if block_given?
          connect_with_callback(headers, &block)
        else
          connect_with_enumerator(headers)
        end
      end

      ##
      # Disconnect from SSE endpoint
      #
      def disconnect
        @mutex.synchronize do
          @connection_state = :disconnected
          stop_heartbeat
          @event_buffer.clear
        end

        emit_event(SSEEvent.new(type: "connection_closed", data: { reason: "manual_disconnect" }))
      end

      ##
      # Add event listener for specific event type
      #
      # @param event_type [String] Event type to listen for
      # @param &block [Proc] Event handler block
      #
      def on(event_type, &block)
        @event_listeners[event_type.to_s] << block if block_given?
      end

      ##
      # Remove event listener
      #
      # @param event_type [String] Event type
      # @param handler [Proc] Handler to remove (optional, removes all if nil)
      #
      def off(event_type, handler = nil)
        if handler
          @event_listeners[event_type.to_s].delete(handler)
        else
          @event_listeners[event_type.to_s].clear
        end
      end

      ##
      # Send data to SSE endpoint (for bidirectional communication)
      #
      # @param data [Hash] Data to send
      # @param event_type [String] Event type
      # @return [Boolean] Success status
      #
      def send_data(data, event_type: "message")
        return false unless @connection_state == :connected

        # This would typically use a separate HTTP connection for sending
        # as SSE is primarily unidirectional from server to client
        begin
          http_transport = A2A::Transport::Http.new(@url.gsub("/events", ""))
          response = http_transport.post(
            "/events/send",
            body: {
              type: event_type,
              data: data,
              last_event_id: @last_event_id
            }
          )
          response.status == 200
        rescue StandardError => e
          emit_event(SSEEvent.new(type: "error", data: { error: e.message }))
          false
        end
      end

      ##
      # Get connection status
      #
      # @return [Symbol] Connection state (:disconnected, :connecting, :connected, :reconnecting)
      #
      def connected?
        @connection_state == :connected
      end

      ##
      # Get buffered events
      #
      # @return [Array<SSEEvent>] Buffered events
      #
      def buffered_events
        @event_buffer.to_a
      end

      ##
      # Clear event buffer
      #
      def clear_buffer!
        @event_buffer.clear
      end

      private

      ##
      # Connect with callback-based handling
      #
      # @param headers [Hash] Request headers
      # @yield [event] Event handler block
      #
      def connect_with_callback(headers)
        Thread.new do
          establish_connection(headers) do |event|
            yield(event) if block_given?
          end
        rescue StandardError => e
          handle_connection_error(e)
        end
      end

      ##
      # Connect with enumerator-based handling
      #
      # @param headers [Hash] Request headers
      # @return [Enumerator] Event stream enumerator
      #
      def connect_with_enumerator(headers)
        Enumerator.new do |yielder|
          establish_connection(headers) do |event|
            yielder << event
          end
        end
      end

      ##
      # Establish SSE connection
      #
      # @param headers [Hash] Request headers
      # @yield [event] Event handler block
      #
      def establish_connection(headers, &block)
        request_headers = build_headers(headers)

        # Use HTTP transport for the underlying connection
        http = A2A::Transport::Http.new(@url, timeout: @config[:timeout])

        http.get(headers: request_headers) do |req|
          req.options.on_data = proc do |chunk, _size|
            process_chunk(chunk, &block)
          end
        end

        @connection_state = :connected
        start_heartbeat
        emit_event(SSEEvent.new(type: "connection_established", data: { url: @url }))
      rescue StandardError => e
        handle_connection_error(e)
      end

      ##
      # Process incoming data chunk
      #
      # @param chunk [String] Data chunk
      # @yield [event] Event handler block
      #
      def process_chunk(chunk, &block)
        lines = chunk.split("\n")

        lines.each do |line|
          event = parse_sse_line(line.strip)
          next unless event

          @last_event_id = event.id if event.id
          buffer_event(event)
          emit_event(event, &block)
        end
      end

      ##
      # Parse SSE line into event
      #
      # @param line [String] SSE line
      # @return [SSEEvent, nil] Parsed event or nil
      #
      def parse_sse_line(line)
        return nil if line.empty? || line.start_with?(":")

        if line.start_with?("data: ")
          data_content = line[6..]
          begin
            data = JSON.parse(data_content)
            SSEEvent.new(
              type: data["type"] || "message",
              data: data["data"] || data,
              id: data["id"],
              retry_interval: data["retry"]
            )
          rescue JSON::ParserError
            SSEEvent.new(type: "message", data: data_content)
          end
        elsif line.start_with?("event: ")
          # Store event type for next data line (simplified parsing)
          nil
        elsif line.start_with?("id: ")
          # Store event ID for next data line (simplified parsing)
          nil
        elsif line.start_with?("retry: ")
          # Update reconnection delay
          @config[:reconnect_delay] = line[7..].to_i
          nil
        else
          nil
        end
      end

      ##
      # Buffer event for replay
      #
      # @param event [SSEEvent] Event to buffer
      #
      def buffer_event(event)
        @event_buffer << event

        # Limit buffer size
        @event_buffer.shift while @event_buffer.size > @config[:buffer_size]
      end

      ##
      # Emit event to listeners
      #
      # @param event [SSEEvent] Event to emit
      # @yield [event] Event handler block
      #
      def emit_event(event)
        # Call specific event listeners
        @event_listeners[event.type].each do |listener|
          listener.call(event)
        rescue StandardError => e
          # Log error but don't stop processing
          Rails.logger.debug { "Error in event listener: #{e.message}" }
        end

        # Call generic block handler
        yield(event) if block_given?
      end

      ##
      # Handle connection errors
      #
      # @param error [Exception] Connection error
      #
      def handle_connection_error(error)
        @connection_state = :disconnected
        stop_heartbeat

        error_event = SSEEvent.new(
          type: "error",
          data: {
            error: error.message,
            reconnect_attempts: @reconnect_attempts
          }
        )
        emit_event(error_event)

        # Attempt reconnection if enabled
        return unless @config[:auto_reconnect] && @reconnect_attempts < @config[:max_reconnect_attempts]

        schedule_reconnection
      end

      ##
      # Schedule reconnection attempt
      #
      def schedule_reconnection
        @reconnect_attempts += 1
        @connection_state = :reconnecting

        Thread.new do
          sleep(@config[:reconnect_delay] / 1000.0)
          connect if @connection_state == :reconnecting
        end
      end

      ##
      # Start heartbeat timer
      #
      def start_heartbeat
        return unless @config[:heartbeat_interval].positive?

        @heartbeat_timer = Thread.new do
          loop do
            sleep(@config[:heartbeat_interval])
            break unless @connection_state == :connected

            emit_event(SSEEvent.new(
                         type: "heartbeat",
                         data: { timestamp: Time.now.iso8601 }
                       ))
          end
        end
      end

      ##
      # Stop heartbeat timer
      #
      def stop_heartbeat
        @heartbeat_timer&.kill
        @heartbeat_timer = nil
      end

      ##
      # Build request headers
      #
      # @param additional_headers [Hash] Additional headers
      # @return [Hash] Complete headers
      #
      def build_headers(additional_headers = {})
        headers = {
          "Accept" => "text/event-stream",
          "Cache-Control" => "no-cache"
        }

        headers["Last-Event-ID"] = @last_event_id if @last_event_id
        headers.merge(@config[:headers]).merge(additional_headers)
      end

      ##
      # Build default configuration
      #
      # @return [Hash] Default configuration
      #
      def default_config
        {
          heartbeat_interval: DEFAULT_HEARTBEAT_INTERVAL,
          reconnect_delay: DEFAULT_RECONNECT_DELAY,
          max_reconnect_attempts: DEFAULT_MAX_RECONNECT_ATTEMPTS,
          buffer_size: DEFAULT_BUFFER_SIZE,
          timeout: DEFAULT_TIMEOUT,
          headers: {},
          auto_reconnect: true,
          last_event_id: nil
        }
      end
    end

    ##
    # SSE Event representation
    #
    class SSEEvent
      attr_reader :type, :data, :id, :retry, :timestamp

      ##
      # Initialize SSE event
      #
      # @param type [String] Event type
      # @param data [Object] Event data
      # @param id [String, nil] Event ID
      # @param retry_interval [Integer, nil] Retry interval
      #
      def initialize(type:, data: nil, id: nil, retry_interval: nil)
        @type = type.to_s
        @data = data
        @id = id
        @retry = retry_interval
        @timestamp = Time.now
      end

      ##
      # Convert event to SSE format
      #
      # @return [String] SSE formatted string
      #
      def to_sse_format
        lines = []
        lines << "event: #{@type}" if @type != "message"
        lines << "id: #{@id}" if @id
        lines << "retry: #{@retry}" if @retry

        data_json = @data.is_a?(String) ? @data : @data.to_json
        data_json.split("\n").each do |line|
          lines << "data: #{line}"
        end

        lines << ""
        lines.join("\n")
      end

      ##
      # Convert to hash representation
      #
      # @return [Hash] Event as hash
      #
      def to_h
        {
          type: @type,
          data: @data,
          id: @id,
          retry: @retry,
          timestamp: @timestamp.iso8601
        }.compact
      end

      ##
      # Check if event is of specific type
      #
      # @param event_type [String] Event type to check
      # @return [Boolean] True if event matches type
      #
      def type?(event_type)
        @type == event_type.to_s
      end

      ##
      # Check if event has data
      #
      # @return [Boolean] True if event has data
      #
      def has_data?
        !@data.nil?
      end
    end
  end
end
