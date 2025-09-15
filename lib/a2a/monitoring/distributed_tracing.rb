# frozen_string_literal: true

require "securerandom"

module A2A
  module Monitoring
  end
end

##
# Distributed tracing implementation for A2A operations
#
# Provides OpenTelemetry-compatible distributed tracing to track requests
# across service boundaries and identify performance bottlenecks.
#
module A2A
  module Monitoring
    class DistributedTracing
      # Trace context headers
      TRACE_PARENT_HEADER = "traceparent"
      TRACE_STATE_HEADER = "tracestate"

      # Span kinds
      SPAN_KIND_CLIENT = "client"
      SPAN_KIND_SERVER = "server"
      SPAN_KIND_INTERNAL = "internal"

      class << self
        attr_accessor :tracer, :enabled

        ##
        # Initialize distributed tracing
        #
        # @param tracer [Object] OpenTelemetry tracer instance
        # @param enabled [Boolean] Whether tracing is enabled
        def initialize!(tracer: nil, enabled: true)
          @tracer = tracer
          @enabled = enabled
        end

        ##
        # Start a new span
        #
        # @param name [String] Span name
        # @param kind [String] Span kind
        # @param parent [Span, nil] Parent span
        # @param attributes [Hash] Span attributes
        # @yield [span] Block to execute within span
        # @return [Object] Result of the block
        def trace(name, kind: SPAN_KIND_INTERNAL, parent: nil, **attributes)
          return yield(NoOpSpan.new) unless @enabled

          span = start_span(name, kind: kind, parent: parent, **attributes)

          begin
            result = yield(span)
            span.set_status(:ok)
            result
          rescue StandardError => e
            span.set_status(:error, description: e.message)
            span.record_exception(e)
            raise
          ensure
            span.finish
          end
        end

        ##
        # Start a span without automatic finishing
        #
        # @param name [String] Span name
        # @param kind [String] Span kind
        # @param parent [Span, nil] Parent span
        # @param attributes [Hash] Span attributes
        # @return [Span] Started span
        def start_span(name, kind: SPAN_KIND_INTERNAL, parent: nil, **attributes)
          return NoOpSpan.new unless @enabled

          if @tracer.respond_to?(:start_span)
            # Use OpenTelemetry tracer if available
            @tracer.start_span(name, kind: kind, parent: parent, attributes: attributes)
          else
            # Use built-in span implementation
            Span.new(name, kind: kind, parent: parent, **attributes)
          end
        end

        ##
        # Extract trace context from headers
        #
        # @param headers [Hash] HTTP headers
        # @return [TraceContext, nil] Extracted trace context
        def extract_context(headers)
          return nil unless @enabled

          traceparent = headers[TRACE_PARENT_HEADER] || headers[TRACE_PARENT_HEADER.upcase]
          tracestate = headers[TRACE_STATE_HEADER] || headers[TRACE_STATE_HEADER.upcase]

          return nil unless traceparent

          TraceContext.parse(traceparent, tracestate)
        end

        ##
        # Inject trace context into headers
        #
        # @param headers [Hash] HTTP headers to modify
        # @param context [TraceContext] Trace context to inject
        def inject_context(headers, context)
          return unless @enabled && context

          headers[TRACE_PARENT_HEADER] = context.to_traceparent
          headers[TRACE_STATE_HEADER] = context.tracestate if context.tracestate
        end

        ##
        # Get current span from context
        #
        # @return [Span, nil] Current active span
        def current_span
          return nil unless @enabled

          Thread.current[:a2a_current_span]
        end

        ##
        # Set current span in context
        #
        # @param span [Span] Span to set as current
        def set_current_span(span)
          Thread.current[:a2a_current_span] = span
        end
      end

      ##
      # Trace context for distributed tracing
      #
      class TraceContext
        attr_reader :trace_id, :span_id, :trace_flags, :tracestate

        ##
        # Initialize trace context
        #
        # @param trace_id [String] Trace ID (32 hex characters)
        # @param span_id [String] Span ID (16 hex characters)
        # @param trace_flags [Integer] Trace flags
        # @param tracestate [String, nil] Trace state
        def initialize(trace_id:, span_id:, trace_flags: 1, tracestate: nil)
          @trace_id = trace_id
          @span_id = span_id
          @trace_flags = trace_flags
          @tracestate = tracestate
        end

        ##
        # Parse trace context from traceparent header
        #
        # @param traceparent [String] Traceparent header value
        # @param tracestate [String, nil] Tracestate header value
        # @return [TraceContext, nil] Parsed trace context
        def self.parse(traceparent, tracestate = nil)
          # Format: 00-{trace_id}-{span_id}-{trace_flags}
          parts = traceparent.split("-")
          return nil unless parts.size == 4 && parts[0] == "00"

          new(
            trace_id: parts[1],
            span_id: parts[2],
            trace_flags: parts[3].to_i(16),
            tracestate: tracestate
          )
        rescue StandardError
          nil
        end

        ##
        # Convert to traceparent header format
        #
        # @return [String] Traceparent header value
        def to_traceparent
          "00-#{@trace_id}-#{@span_id}-#{@trace_flags.to_s(16).rjust(2, '0')}"
        end

        ##
        # Create child context with new span ID
        #
        # @return [TraceContext] Child trace context
        def create_child
          self.class.new(
            trace_id: @trace_id,
            span_id: generate_span_id,
            trace_flags: @trace_flags,
            tracestate: @tracestate
          )
        end

        private

        ##
        # Generate a new span ID
        #
        # @return [String] 16-character hex span ID
        def generate_span_id
          SecureRandom.hex(8)
        end
      end

      ##
      # Span implementation for distributed tracing
      #
      class Span
        attr_reader :name, :kind, :trace_id, :span_id, :parent_span_id, :start_time, :end_time, :attributes, :events,
                    :status

        ##
        # Initialize a new span
        #
        # @param name [String] Span name
        # @param kind [String] Span kind
        # @param parent [Span, nil] Parent span
        # @param attributes [Hash] Initial attributes
        def initialize(name, kind: SPAN_KIND_INTERNAL, parent: nil, **attributes)
          @name = name
          @kind = kind
          @trace_id = parent&.trace_id || generate_trace_id
          @span_id = generate_span_id
          @parent_span_id = parent&.span_id
          @start_time = Time.now
          @end_time = nil
          @attributes = attributes
          @events = []
          @status = { code: :unset }

          # Set as current span
          DistributedTracing.set_current_span(self)
        end

        ##
        # Set span attribute
        #
        # @param key [String, Symbol] Attribute key
        # @param value [Object] Attribute value
        def set_attribute(key, value)
          @attributes[key.to_s] = value
        end

        ##
        # Set multiple attributes
        #
        # @param attributes [Hash] Attributes to set
        def set_attributes(**attributes)
          @attributes.merge!(attributes.transform_keys(&:to_s))
        end

        ##
        # Add an event to the span
        #
        # @param name [String] Event name
        # @param attributes [Hash] Event attributes
        # @param timestamp [Time] Event timestamp
        def add_event(name, attributes: {}, timestamp: Time.now)
          @events << {
            name: name,
            attributes: attributes,
            timestamp: timestamp
          }
        end

        ##
        # Record an exception
        #
        # @param exception [Exception] Exception to record
        def record_exception(exception)
          add_event("exception", attributes: {
                      "exception.type" => exception.class.name,
                      "exception.message" => exception.message,
                      "exception.stacktrace" => exception.backtrace&.join("\n")
                    })
        end

        ##
        # Set span status
        #
        # @param code [Symbol] Status code (:ok, :error, :unset)
        # @param description [String, nil] Status description
        def set_status(code, description: nil)
          @status = { code: code, description: description }.compact
        end

        ##
        # Finish the span
        #
        def finish
          @end_time = Time.now

          # Clear from current context if this is the current span
          DistributedTracing.set_current_span(@parent) if DistributedTracing.current_span == self

          # Export span if exporter is available
          export_span
        end

        ##
        # Get span duration in milliseconds
        #
        # @return [Float, nil] Duration in milliseconds
        def duration_ms
          return nil unless @end_time

          (@end_time - @start_time) * 1000
        end

        ##
        # Convert span to hash representation
        #
        # @return [Hash] Span data
        def to_h
          {
            name: @name,
            kind: @kind,
            trace_id: @trace_id,
            span_id: @span_id,
            parent_span_id: @parent_span_id,
            start_time: @start_time.to_f,
            end_time: @end_time&.to_f,
            duration_ms: duration_ms,
            attributes: @attributes,
            events: @events,
            status: @status
          }.compact
        end

        ##
        # Get trace context for this span
        #
        # @return [TraceContext] Trace context
        def trace_context
          TraceContext.new(
            trace_id: @trace_id,
            span_id: @span_id,
            trace_flags: 1
          )
        end

        private

        ##
        # Generate a new trace ID
        #
        # @return [String] 32-character hex trace ID
        def generate_trace_id
          SecureRandom.hex(16)
        end

        ##
        # Generate a new span ID
        #
        # @return [String] 16-character hex span ID
        def generate_span_id
          SecureRandom.hex(8)
        end

        ##
        # Export span to configured exporters
        #
        def export_span
          # This would integrate with OpenTelemetry exporters
          # For now, just log the span if debugging is enabled
          return unless A2A.configuration.debug_tracing

          Rails.logger.debug { "Span: #{to_h.to_json}" }
        end
      end

      ##
      # No-op span for when tracing is disabled
      #
      class NoOpSpan
        def set_attribute(key, value); end
        def set_attributes(**attributes); end
        def add_event(name, **options); end
        def record_exception(exception); end
        def set_status(code, **options); end
        def finish; end

        def trace_context
          nil
        end
      end
    end
  end
end
