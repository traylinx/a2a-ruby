# frozen_string_literal: true

require_relative "event_queue"

module A2A
  module Server
    module Events
      ##
      # Event consumer for processing events from an event queue
      #
      # Provides functionality to consume events from an EventQueue and process them
      # with registered handlers. Supports filtering and error handling.
      #
      class EventConsumer
        attr_reader :queue, :handlers, :running

        ##
        # Initialize a new event consumer
        #
        # @param queue [EventQueue] The event queue to consume from
        def initialize(queue)
          @queue = queue
          @handlers = {}
          @running = false
          @thread = nil
          @mutex = Mutex.new
        end

        ##
        # Register a handler for a specific event type
        #
        # @param event_type [String] The event type to handle
        # @param handler [Proc] The handler proc that receives the event
        def register_handler(event_type, &handler)
          @mutex.synchronize do
            @handlers[event_type] ||= []
            @handlers[event_type] << handler
          end
        end

        ##
        # Remove a handler for a specific event type
        #
        # @param event_type [String] The event type
        # @param handler [Proc] The handler to remove
        def remove_handler(event_type, handler)
          @mutex.synchronize do
            @handlers[event_type]&.delete(handler)
            @handlers.delete(event_type) if @handlers[event_type] && @handlers[event_type].empty?
          end
        end

        ##
        # Start consuming events in a background thread
        #
        # @param filter [Proc, nil] Optional filter for events
        def start(filter = nil)
          return if @running

          @running = true
          @thread = Thread.new do
            consume_events(filter)
          end
        end

        ##
        # Stop consuming events
        def stop
          @running = false
          @thread&.join
          @thread = nil
        end

        ##
        # Process a single event synchronously
        #
        # @param event [Event] The event to process
        def process_event(event)
          handlers = @mutex.synchronize { @handlers[event.type]&.dup || [] }

          handlers.each do |handler|
            handler.call(event)
          rescue StandardError => e
            handle_error(event, e)
          end
        end

        private

        ##
        # Consume events from the queue
        #
        # @param filter [Proc, nil] Optional event filter
        def consume_events(filter)
          @queue.subscribe(filter) do |event|
            break unless @running

            process_event(event)
          end
        rescue StandardError => e
          handle_error(nil, e)
        end

        ##
        # Handle errors during event processing
        #
        # @param event [Event, nil] The event being processed (if any)
        # @param error [StandardError] The error that occurred
        def handle_error(event, error)
          warn "Error processing event #{event&.id}: #{error.message}"
          warn error.backtrace.join("\n") if error.backtrace
        end
      end
    end
  end
end
