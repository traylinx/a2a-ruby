# frozen_string_literal: true

require_relative "middleware/retry_interceptor"
require_relative "middleware/logging_interceptor"
require_relative "middleware/rate_limit_interceptor"
require_relative "middleware/circuit_breaker_interceptor"

##
# Client middleware system for A2A requests
#
# Provides a collection of middleware interceptors for handling
# cross-cutting concerns like retries, logging, rate limiting,
# and circuit breaking.
#
# @example Using middleware with a client
#   retry_middleware = A2A::Client::Middleware::RetryInterceptor.new(max_attempts: 3)
#   logging_middleware = A2A::Client::Middleware::LoggingInterceptor.new
#
#   client = A2A::Client::HttpClient.new(
#     'https://agent.example.com',
#     middleware: [retry_middleware, logging_middleware]
#   )
#
module A2A::Client::Middleware
  ##
  # Base class for middleware interceptors
  #
  class Base
    ##
    # Call the middleware
    #
    # @param request [Object] The request object
    # @param context [Hash] Request context
    # @param next_middleware [Proc] Next middleware in chain
    # @return [Object] Response from next middleware
    def call(request, context, next_middleware)
      raise NotImplementedError, "#{self.class}#call must be implemented"
    end
  end

  ##
  # Create middleware from configuration
  #
  # @param config [Hash] Middleware configuration
  # @return [Base] Configured middleware instance
  def self.from_config(config)
    type = config["type"] || config[:type]

    case type
    when "retry"
      RetryInterceptor.new(
        max_attempts: config["max_attempts"] || config[:max_attempts] || 3,
        initial_delay: config["initial_delay"] || config[:initial_delay] || 1.0,
        max_delay: config["max_delay"] || config[:max_delay] || 60.0,
        backoff_multiplier: config["backoff_multiplier"] || config[:backoff_multiplier] || 2.0,
        retryable_errors: config["retryable_errors"] || config[:retryable_errors]
      )
    when "logging"
      LoggingInterceptor.new(
        logger: config["logger"] || config[:logger],
        log_level: config["log_level"] || config[:log_level] || :info,
        log_requests: config["log_requests"] || config[:log_requests] || true,
        log_responses: config["log_responses"] || config[:log_responses] || true,
        log_errors: config["log_errors"] || config[:log_errors] || true
      )
    when "rate_limit"
      RateLimitInterceptor.new(
        requests_per_second: config["requests_per_second"] || config[:requests_per_second] || 10,
        burst_size: config["burst_size"] || config[:burst_size] || 20
      )
    when "circuit_breaker"
      CircuitBreakerInterceptor.new(
        failure_threshold: config["failure_threshold"] || config[:failure_threshold] || 5,
        timeout: config["timeout"] || config[:timeout] || 60,
        expected_errors: config["expected_errors"] || config[:expected_errors]
      )
    else
      raise ArgumentError, "Unknown middleware type: #{type}"
    end
  end

  ##
  # Create default middleware stack
  #
  # @param config [Hash] Configuration options
  # @return [Array<Base>] Default middleware stack
  def self.default_stack(config = {})
    stack = []

    # Add retry middleware
    stack << RetryInterceptor.new if config.fetch("retry", true)

    # Add logging middleware
    stack << LoggingInterceptor.new if config.fetch("logging", true)

    # Add rate limiting if configured
    if config["rate_limit"]
      stack << RateLimitInterceptor.new(
        requests_per_second: config["rate_limit"]["requests_per_second"] || 10
      )
    end

    # Add circuit breaker if configured
    if config["circuit_breaker"]
      stack << CircuitBreakerInterceptor.new(
        failure_threshold: config["circuit_breaker"]["failure_threshold"] || 5
      )
    end

    stack
  end
end
