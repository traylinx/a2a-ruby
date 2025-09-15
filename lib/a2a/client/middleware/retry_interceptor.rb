# frozen_string_literal: true

module A2A
  module Client
    module Middleware
      ##
      # Retry interceptor with exponential backoff
      #
      # Automatically retries failed requests with configurable backoff
      # strategy and error filtering.
      #
      class RetryInterceptor < Base
        attr_reader :max_attempts, :initial_delay, :max_delay, :backoff_multiplier, :retryable_errors

        # Default retryable error classes
        DEFAULT_RETRYABLE_ERRORS = [
          A2A::Errors::TimeoutError,
          A2A::Errors::HTTPError,
          A2A::Errors::TransportError,
          A2A::Errors::AgentUnavailable,
          A2A::Errors::ResourceExhausted,
          Faraday::TimeoutError,
          Faraday::ConnectionFailed
        ].freeze

        ##
        # Initialize retry interceptor
        #
        # @param max_attempts [Integer] Maximum number of retry attempts (default: 3)
        # @param initial_delay [Float] Initial delay in seconds (default: 1.0)
        # @param max_delay [Float] Maximum delay in seconds (default: 60.0)
        # @param backoff_multiplier [Float] Backoff multiplier (default: 2.0)
        # @param retryable_errors [Array<Class>] List of retryable error classes
        def initialize(max_attempts: 3, initial_delay: 1.0, max_delay: 60.0, 
                       backoff_multiplier: 2.0, retryable_errors: nil)
          @max_attempts = max_attempts
          @initial_delay = initial_delay
          @max_delay = max_delay
          @backoff_multiplier = backoff_multiplier
          @retryable_errors = retryable_errors || DEFAULT_RETRYABLE_ERRORS
          
          validate_configuration!
        end

        ##
        # Execute request with retry logic
        #
        # @param request [Object] The request object
        # @param context [Hash] Request context
        # @param next_middleware [Proc] Next middleware in chain
        # @return [Object] Response from successful request
        def call(request, context, next_middleware)
          attempt = 0
          last_error = nil

          loop do
            attempt += 1
            
            begin
              return next_middleware.call(request, context)
            rescue => error
              last_error = error
              
              # Check if we should retry
              if should_retry?(error, attempt)
                delay = calculate_delay(attempt)
                context[:retry_attempt] = attempt
                context[:retry_delay] = delay
                
                sleep(delay) if delay > 0
                next
              else
                # Re-raise the error if we shouldn't retry or max attempts reached
                raise error
              end
            end
          end
        end

        ##
        # Check if an error should trigger a retry
        #
        # @param error [Exception] The error that occurred
        # @param attempt [Integer] Current attempt number
        # @return [Boolean] True if should retry
        def should_retry?(error, attempt)
          return false if attempt >= @max_attempts
          return false unless retryable_error?(error)
          
          # Check for specific HTTP status codes that shouldn't be retried
          if error.respond_to?(:status_code)
            case error.status_code
            when 400, 401, 403, 404, 422 # Client errors - don't retry
              return false
            when 429 # Rate limited - should retry
              return true
            when 500..599 # Server errors - should retry
              return true
            end
          end
          
          true
        end

        ##
        # Check if an error is retryable
        #
        # @param error [Exception] The error to check
        # @return [Boolean] True if error is retryable
        def retryable_error?(error)
          @retryable_errors.any? { |error_class| error.is_a?(error_class) }
        end

        ##
        # Calculate delay for the given attempt
        #
        # @param attempt [Integer] Current attempt number (1-based)
        # @return [Float] Delay in seconds
        def calculate_delay(attempt)
          return 0 if attempt <= 1
          
          # Exponential backoff: initial_delay * (backoff_multiplier ^ (attempt - 2))
          delay = @initial_delay * (@backoff_multiplier ** (attempt - 2))
          
          # Add jitter to prevent thundering herd
          jitter = delay * 0.1 * rand
          delay += jitter
          
          # Cap at max_delay
          [delay, @max_delay].min
        end

        ##
        # Get retry statistics
        #
        # @return [Hash] Retry configuration and statistics
        def stats
          {
            max_attempts: @max_attempts,
            initial_delay: @initial_delay,
            max_delay: @max_delay,
            backoff_multiplier: @backoff_multiplier,
            retryable_errors: @retryable_errors.map(&:name)
          }
        end

        private

        ##
        # Validate configuration parameters
        def validate_configuration!
          raise ArgumentError, "max_attempts must be positive" if @max_attempts <= 0
          raise ArgumentError, "initial_delay must be non-negative" if @initial_delay < 0
          raise ArgumentError, "max_delay must be positive" if @max_delay <= 0
          raise ArgumentError, "backoff_multiplier must be positive" if @backoff_multiplier <= 0
          
          if @initial_delay > @max_delay
            raise ArgumentError, "initial_delay cannot be greater than max_delay"
          end
        end
      end
    end
  end
end