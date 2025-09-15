# frozen_string_literal: true

##
# Circuit breaker interceptor for fault tolerance
#
# Implements the circuit breaker pattern to prevent cascading failures
# by temporarily stopping requests to a failing service.
#
module A2A
  module Client
    module Middleware
      class CircuitBreakerInterceptor
        # Circuit breaker states
        CLOSED = :closed
        OPEN = :open
        HALF_OPEN = :half_open

        attr_reader :failure_threshold, :timeout, :expected_errors, :state,
                    :failure_count, :last_failure_time, :success_count

        ##
        # Initialize circuit breaker interceptor
        #
        # @param failure_threshold [Integer] Number of failures before opening circuit (default: 5)
        # @param timeout [Integer] Timeout in seconds before trying half-open (default: 60)
        # @param expected_errors [Array<Class>] Error classes that should trigger circuit breaker
        def initialize(failure_threshold: 5, timeout: 60, expected_errors: nil)
          @failure_threshold = failure_threshold
          @timeout = timeout
          @expected_errors = expected_errors || default_expected_errors
          @state = CLOSED
          @failure_count = 0
          @success_count = 0
          @last_failure_time = nil
          @mutex = Mutex.new

          validate_configuration!
        end

        ##
        # Execute request with circuit breaker logic
        #
        # @param request [Object] The request object
        # @param context [Hash] Request context
        # @param next_middleware [Proc] Next middleware in chain
        # @return [Object] Response from next middleware
        def call(request, context, next_middleware)
          @mutex.synchronize do
            case @state
            when CLOSED
              execute_request(request, context, next_middleware)
            when OPEN
              check_timeout_and_execute(request, context, next_middleware)
            when HALF_OPEN
              execute_half_open_request(request, context, next_middleware)
            end
          end
        end

        ##
        # Get current circuit breaker status
        #
        # @return [Hash] Circuit breaker status information
        def status
          @mutex.synchronize do
            {
              state: @state,
              failure_count: @failure_count,
              success_count: @success_count,
              failure_threshold: @failure_threshold,
              timeout: @timeout,
              last_failure_time: @last_failure_time,
              time_until_half_open: time_until_half_open
            }
          end
        end

        ##
        # Check if the circuit breaker is open
        #
        # @return [Boolean] True if circuit is open
        def open?
          @state == OPEN
        end

        ##
        # Check if the circuit breaker is closed
        #
        # @return [Boolean] True if circuit is closed
        def closed?
          @state == CLOSED
        end

        ##
        # Check if the circuit breaker is half-open
        #
        # @return [Boolean] True if circuit is half-open
        def half_open?
          @state == HALF_OPEN
        end

        ##
        # Reset the circuit breaker to closed state
        def reset!
          @mutex.synchronize do
            @state = CLOSED
            @failure_count = 0
            @success_count = 0
            @last_failure_time = nil
          end
        end

        ##
        # Force the circuit breaker to open state
        def trip!
          @mutex.synchronize do
            @state = OPEN
            @last_failure_time = Time.now
          end
        end

        private

        ##
        # Execute request in closed state
        def execute_request(request, context, next_middleware)
          response = next_middleware.call(request, context)
          on_success
          response
        rescue StandardError => e
          on_failure if circuit_breaker_error?(e)
          raise e
        end

        ##
        # Check timeout and execute request when circuit is open
        def check_timeout_and_execute(request, context, next_middleware)
          raise A2A::Errors::AgentUnavailable, "Circuit breaker is OPEN. Service unavailable." unless timeout_expired?

          @state = HALF_OPEN
          @success_count = 0
          execute_half_open_request(request, context, next_middleware)
        end

        ##
        # Execute request in half-open state
        def execute_half_open_request(request, context, next_middleware)
          response = next_middleware.call(request, context)
          on_half_open_success
          response
        rescue StandardError => e
          on_half_open_failure if circuit_breaker_error?(e)
          raise e
        end

        ##
        # Handle successful request
        def on_success
          @failure_count = 0
        end

        ##
        # Handle failed request
        def on_failure
          @failure_count += 1
          @last_failure_time = Time.now

          return unless @failure_count >= @failure_threshold

          @state = OPEN
        end

        ##
        # Handle successful request in half-open state
        def on_half_open_success
          @success_count += 1

          # Close circuit after successful request in half-open state
          @state = CLOSED
          @failure_count = 0
          @success_count = 0
        end

        ##
        # Handle failed request in half-open state
        def on_half_open_failure
          @state = OPEN
          @failure_count += 1
          @last_failure_time = Time.now
        end

        ##
        # Check if timeout has expired for opening circuit
        def timeout_expired?
          return false unless @last_failure_time

          Time.now - @last_failure_time >= @timeout
        end

        ##
        # Calculate time until circuit can be half-open
        def time_until_half_open
          return 0 unless @state == OPEN && @last_failure_time

          elapsed = Time.now - @last_failure_time
          remaining = @timeout - elapsed
          [remaining, 0].max
        end

        ##
        # Check if error should trigger circuit breaker
        def circuit_breaker_error?(error)
          @expected_errors.any? { |error_class| error.is_a?(error_class) }
        end

        ##
        # Default error classes that should trigger circuit breaker
        def default_expected_errors
          [
            A2A::Errors::TimeoutError,
            A2A::Errors::HTTPError,
            A2A::Errors::TransportError,
            A2A::Errors::AgentUnavailable,
            A2A::Errors::ResourceExhausted,
            A2A::Errors::InternalError,
            Faraday::TimeoutError,
            Faraday::ConnectionFailed
          ]
        end

        ##
        # Validate configuration parameters
        def validate_configuration!
          raise ArgumentError, "failure_threshold must be positive" if @failure_threshold <= 0

          raise ArgumentError, "timeout must be positive" if @timeout <= 0

          return if @expected_errors.is_a?(Array)

          raise ArgumentError, "expected_errors must be an array"
        end
      end
    end
  end
end
