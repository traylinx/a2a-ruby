# frozen_string_literal: true

##
# Rate limiting interceptor using token bucket algorithm
#
# Implements client-side rate limiting to prevent overwhelming
# the target agent with too many requests.
#
module A2A
  module Client
    module Middleware
      class RateLimitInterceptor
        attr_reader :requests_per_second, :burst_size, :tokens, :last_refill

        ##
        # Initialize rate limit interceptor
        #
        # @param requests_per_second [Numeric] Maximum requests per second (default: 10)
        # @param burst_size [Integer] Maximum burst size (default: 20)
        def initialize(requests_per_second: 10, burst_size: 20)
          @requests_per_second = requests_per_second.to_f
          @burst_size = burst_size
          @tokens = @burst_size.to_f
          @last_refill = Time.now
          @mutex = Mutex.new

          validate_configuration!
        end

        ##
        # Execute request with rate limiting
        #
        # @param request [Object] The request object
        # @param context [Hash] Request context
        # @param next_middleware [Proc] Next middleware in chain
        # @return [Object] Response from next middleware
        def call(request, context, next_middleware)
          wait_for_token
          next_middleware.call(request, context)
        end

        ##
        # Check if a request can be made immediately
        #
        # @return [Boolean] True if request can be made without waiting
        def can_make_request?
          @mutex.synchronize do
            refill_tokens
            @tokens >= 1.0
          end
        end

        ##
        # Get current rate limit status
        #
        # @return [Hash] Rate limit status information
        def status
          @mutex.synchronize do
            refill_tokens
            {
              requests_per_second: @requests_per_second,
              burst_size: @burst_size,
              available_tokens: @tokens.round(2),
              tokens_full: @tokens >= @burst_size,
              can_make_request: @tokens >= 1.0
            }
          end
        end

        ##
        # Calculate time until next token is available
        #
        # @return [Float] Time in seconds until next token
        def time_until_next_token
          @mutex.synchronize do
            refill_tokens
            return 0.0 if @tokens >= 1.0

            tokens_needed = 1.0 - @tokens
            tokens_needed / @requests_per_second
          end
        end

        ##
        # Reset the rate limiter (useful for testing)
        def reset!
          @mutex.synchronize do
            @tokens = @burst_size.to_f
            @last_refill = Time.now
          end
        end

        private

        ##
        # Wait for a token to become available
        def wait_for_token
          loop do
            @mutex.synchronize do
              refill_tokens

              if @tokens >= 1.0
                @tokens -= 1.0
                return
              end
            end

            # Calculate how long to sleep
            sleep_time = time_until_next_token
            sleep(sleep_time) if sleep_time.positive?
          end
        end

        ##
        # Refill tokens based on elapsed time
        def refill_tokens
          now = Time.now
          elapsed = now - @last_refill

          return unless elapsed.positive?

          # Add tokens based on elapsed time
          tokens_to_add = elapsed * @requests_per_second
          @tokens = [@tokens + tokens_to_add, @burst_size].min
          @last_refill = now
        end

        ##
        # Validate configuration parameters
        def validate_configuration!
          raise ArgumentError, "requests_per_second must be positive" if @requests_per_second <= 0

          raise ArgumentError, "burst_size must be positive" if @burst_size <= 0

          return unless @burst_size < @requests_per_second

          warn "Warning: burst_size (#{@burst_size}) is less than requests_per_second (#{@requests_per_second})"
        end
      end
    end
  end
end
