# frozen_string_literal: true

module A2A
  module Server
    module Events
      ##
      # Event object for the event queue system
      #
      # Represents an event that can be published to and consumed from an event queue.
      # Events can be Task objects, Message objects, or status/artifact update events.
      #
      class Event
        attr_reader :type, :data, :timestamp, :id

        ##
        # Initialize a new event
        #
        # @param type [String] The event type (e.g., 'task', 'message', 'task_status_update')
        # @param data [Object] The event data (Task, Message, or update event object)
        # @param id [String, nil] Optional event ID (generated if not provided)
        def initialize(type:, data:, id: nil)
          @type = type
          @data = data
          @timestamp = Time.now.utc
          @id = id || SecureRandom.uuid
        end

        ##
        # Convert event to hash representation
        #
        # @return [Hash] Hash representation of the event
        def to_h
          {
            id: @id,
            type: @type,
            data: @data.respond_to?(:to_h) ? @data.to_h : @data,
            timestamp: @timestamp.iso8601
          }
        end

        ##
        # Check if this is a task-related event
        #
        # @return [Boolean] True if the event is task-related
        def task_event?
          %w[task task_status_update task_artifact_update].include?(@type)
        end

        ##
        # Check if this is a message event
        #
        # @return [Boolean] True if the event is a message
        def message_event?
          @type == "message"
        end

        ##
        # Get the task ID from the event data if available
        #
        # @return [String, nil] The task ID or nil if not available
        def task_id
          case @data
          when A2A::Types::Task
            @data.id
          when A2A::Types::TaskStatusUpdateEvent, A2A::Types::TaskArtifactUpdateEvent
            @data.task_id
          else
            nil
          end
        end

        ##
        # Get the context ID from the event data if available
        #
        # @return [String, nil] The context ID or nil if not available
        def context_id
          case @data
          when A2A::Types::Task
            @data.context_id
          when A2A::Types::TaskStatusUpdateEvent, A2A::Types::TaskArtifactUpdateEvent
            @data.context_id
          when A2A::Types::Message
            @data.context_id
          else
            nil
          end
        end
      end

      ##
      # Abstract base class for event queues
      #
      # Defines the interface for event queue implementations that can be used
      # to publish and consume events during agent execution.
      #
      class EventQueue
        ##
        # Publish an event to the queue
        #
        # @param event [Event] The event to publish
        # @abstract Subclasses must implement this method
        def publish(event)
          raise NotImplementedError, "Subclasses must implement publish"
        end

        ##
        # Subscribe to events from the queue
        #
        # @param filter [Proc, nil] Optional filter to apply to events
        # @return [Enumerator] Enumerator yielding events
        # @abstract Subclasses must implement this method
        def subscribe(filter = nil)
          raise NotImplementedError, "Subclasses must implement subscribe"
        end

        ##
        # Close the event queue and clean up resources
        #
        # @abstract Subclasses must implement this method
        def close
          raise NotImplementedError, "Subclasses must implement close"
        end

        ##
        # Check if the queue is closed
        #
        # @return [Boolean] True if the queue is closed
        # @abstract Subclasses must implement this method
        def closed?
          raise NotImplementedError, "Subclasses must implement closed?"
        end
      end

      ##
      # In-memory event queue implementation
      #
      # A simple in-memory event queue that uses Ruby's Queue class for
      # thread-safe event publishing and consumption.
      #
      class InMemoryEventQueue < EventQueue
        def initialize
          @queue = Queue.new
          @subscribers = []
          @closed = false
          @mutex = Mutex.new
        end

        ##
        # Publish an event to all subscribers
        #
        # @param event [Event] The event to publish
        def publish(event)
          return if @closed

          @mutex.synchronize do
            @subscribers.each do |subscriber|
              subscriber[:queue].push(event) if subscriber[:filter].nil? || subscriber[:filter].call(event)
            rescue StandardError => e
              # Log error but don't fail the publish operation
              warn "Error publishing to subscriber: #{e.message}"
            end
          end
        end

        ##
        # Subscribe to events with optional filtering
        #
        # @param filter [Proc, nil] Optional filter proc that receives an event and returns boolean
        # @return [Enumerator] Enumerator that yields events
        def subscribe(filter = nil)
          return enum_for(:subscribe, filter) unless block_given?

          subscriber_queue = Queue.new
          subscriber = { queue: subscriber_queue, filter: filter }

          @mutex.synchronize do
            @subscribers << subscriber
          end

          begin
            loop do
              break if @closed

              begin
                event = subscriber_queue.pop(true) # Non-blocking pop
                yield event
              rescue ThreadError
                # Queue is empty, sleep briefly and try again
                sleep 0.001 # Reduced sleep time for better responsiveness
              end
            end
          ensure
            @mutex.synchronize do
              @subscribers.delete(subscriber)
            end
          end
        end

        ##
        # Close the event queue
        def close
          @closed = true
          @mutex.synchronize do
            @subscribers.clear
          end
        end

        ##
        # Check if the queue is closed
        #
        # @return [Boolean] True if closed
        def closed?
          @closed
        end

        ##
        # Get the number of active subscribers
        #
        # @return [Integer] Number of subscribers
        def subscriber_count
          @mutex.synchronize { @subscribers.length }
        end
      end
    end
  end
end
