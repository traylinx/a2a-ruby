# frozen_string_literal: true

require "logger"
require "json"

##
# Logging interceptor for request/response debugging
#
# Provides comprehensive logging of A2A requests, responses, and errors
# with configurable log levels and filtering.
#
class A2A::Client::Middleware::LoggingInterceptor
  attr_reader :logger, :log_level, :log_requests, :log_responses, :log_errors

  ##
  # Initialize logging interceptor
  #
  # @param logger [Logger, nil] Logger instance (creates default if nil)
  # @param log_level [Symbol] Log level (:debug, :info, :warn, :error)
  # @param log_requests [Boolean] Whether to log requests (default: true)
  # @param log_responses [Boolean] Whether to log responses (default: true)
  # @param log_errors [Boolean] Whether to log errors (default: true)
  # @param mask_sensitive [Boolean] Whether to mask sensitive data (default: true)
  def initialize(logger: nil, log_level: :info, log_requests: true,
    log_responses: true, log_errors: true, mask_sensitive: true)
    @logger = logger || create_default_logger
    @log_level = log_level
    @log_requests = log_requests
    @log_responses = log_responses
    @log_errors = log_errors
    @mask_sensitive = mask_sensitive

    validate_configuration!
  end

  ##
  # Execute request with logging
  #
  # @param request [Object] The request object
  # @param context [Hash] Request context
  # @param next_middleware [Proc] Next middleware in chain
  # @return [Object] Response from next middleware
  def call(request, context, next_middleware)
    request_id = context[:request_id] || generate_request_id
    context[:request_id] = request_id

    start_time = Time.now

    log_request(request, context) if @log_requests

    begin
      response = next_middleware.call(request, context)

      duration = Time.now - start_time
      log_response(response, context, duration) if @log_responses

      response
    rescue StandardError => e
      duration = Time.now - start_time
      log_error(e, context, duration) if @log_errors
      raise e
    end
  end

  ##
  # Log a request
  #
  # @param request [Object] The request object
  # @param context [Hash] Request context
  def log_request(request, context)
    log_data = {
      type: "request",
      request_id: context[:request_id],
      timestamp: Time.now.utc.iso8601,
      method: extract_method(request),
      url: extract_url(request),
      headers: mask_headers(extract_headers(request)),
      body: mask_body(extract_body(request)),
      context: sanitize_context(context)
    }

    @logger.send(@log_level, format_log_message("A2A Request", log_data))
  end

  ##
  # Log a response
  #
  # @param response [Object] The response object
  # @param context [Hash] Request context
  # @param duration [Float] Request duration in seconds
  def log_response(response, context, duration)
    log_data = {
      type: "response",
      request_id: context[:request_id],
      timestamp: Time.now.utc.iso8601,
      duration_ms: (duration * 1000).round(2),
      status: extract_status(response),
      headers: mask_headers(extract_response_headers(response)),
      body: mask_body(extract_response_body(response)),
      success: response_successful?(response)
    }

    level = response_successful?(response) ? @log_level : :warn
    @logger.send(level, format_log_message("A2A Response", log_data))
  end

  ##
  # Log an error
  #
  # @param error [Exception] The error that occurred
  # @param context [Hash] Request context
  # @param duration [Float] Request duration in seconds
  def log_error(error, context, duration)
    log_data = {
      type: "error",
      request_id: context[:request_id],
      timestamp: Time.now.utc.iso8601,
      duration_ms: (duration * 1000).round(2),
      error_class: error.class.name,
      error_message: error.message,
      error_code: error.respond_to?(:code) ? error.code : nil,
      backtrace: error.backtrace&.first(10),
      retry_attempt: context[:retry_attempt]
    }

    @logger.error(format_log_message("A2A Error", log_data))
  end

  private

  ##
  # Create default logger
  #
  # @return [Logger] Default logger instance
  def create_default_logger
    logger = Logger.new($stdout)
    logger.level = Logger::INFO
    logger.formatter = proc do |severity, datetime, _progname, msg|
      "[#{datetime.strftime("%Y-%m-%d %H:%M:%S")}] #{severity}: #{msg}\n"
    end
    logger
  end

  ##
  # Generate a unique request ID
  #
  # @return [String] Request ID
  def generate_request_id
    require "securerandom"
    SecureRandom.hex(8)
  end

  ##
  # Format log message
  #
  # @param title [String] Log message title
  # @param data [Hash] Log data
  # @return [String] Formatted log message
  def format_log_message(title, data)
    "#{title}: #{JSON.pretty_generate(data)}"
  rescue JSON::GeneratorError
    "#{title}: #{data.inspect}"
  end

  ##
  # Extract method from request
  #
  # @param request [Object] The request object
  # @return [String, nil] HTTP method or JSON-RPC method
  def extract_method(request)
    if request.respond_to?(:method)
      request.method
    elsif request.respond_to?(:[])
      request["method"] || request[:method]
    end
  end

  ##
  # Extract URL from request
  #
  # @param request [Object] The request object
  # @return [String, nil] Request URL
  def extract_url(request)
    if request.respond_to?(:url)
      request.url
    elsif request.respond_to?(:uri)
      request.uri.to_s
    end
  end

  ##
  # Extract headers from request
  #
  # @param request [Object] The request object
  # @return [Hash] Request headers
  def extract_headers(request)
    if request.respond_to?(:headers)
      request.headers.to_h
    else
      {}
    end
  end

  ##
  # Extract body from request
  #
  # @param request [Object] The request object
  # @return [String, Hash, nil] Request body
  def extract_body(request)
    if request.respond_to?(:body)
      body = request.body
      return parse_json_body(body) if body.is_a?(String)

      body
    elsif request.respond_to?(:to_h)
      request.to_h
    end
  end

  ##
  # Extract status from response
  #
  # @param response [Object] The response object
  # @return [Integer, String, nil] Response status
  def extract_status(response)
    if response.respond_to?(:status)
      response.status
    elsif response.respond_to?(:[])
      response["status"] || response[:status]
    end
  end

  ##
  # Extract headers from response
  #
  # @param response [Object] The response object
  # @return [Hash] Response headers
  def extract_response_headers(response)
    if response.respond_to?(:headers)
      response.headers.to_h
    else
      {}
    end
  end

  ##
  # Extract body from response
  #
  # @param response [Object] The response object
  # @return [String, Hash, nil] Response body
  def extract_response_body(response)
    if response.respond_to?(:body)
      body = response.body
      return parse_json_body(body) if body.is_a?(String)

      body
    elsif response.respond_to?(:to_h)
      response.to_h
    end
  end

  ##
  # Check if response was successful
  #
  # @param response [Object] The response object
  # @return [Boolean] True if successful
  def response_successful?(response)
    if response.respond_to?(:success?)
      response.success?
    elsif response.respond_to?(:status)
      (200..299).cover?(response.status)
    elsif response.respond_to?(:[])
      !response["error"] && !response[:error]
    else
      true # Assume success if we can't determine
    end
  end

  ##
  # Parse JSON body
  #
  # @param body [String] JSON body string
  # @return [Hash, String] Parsed JSON or original string
  def parse_json_body(body)
    JSON.parse(body)
  rescue JSON::ParserError
    body
  end

  ##
  # Mask sensitive headers
  #
  # @param headers [Hash] Headers to mask
  # @return [Hash] Masked headers
  def mask_headers(headers)
    return headers unless @mask_sensitive

    masked = headers.dup

    # Mask authorization headers
    masked.each do |key, value|
      next unless key.to_s.downcase.include?("authorization") ||
        key.to_s.downcase.include?("token") ||
        key.to_s.downcase.include?("key")

      masked[key] = mask_value(value)
    end

    masked
  end

  ##
  # Mask sensitive body content
  #
  # @param body [Object] Body to mask
  # @return [Object] Masked body
  def mask_body(body)
    return body unless @mask_sensitive
    return body unless body.is_a?(Hash)

    masked = body.dup

    # Mask common sensitive fields
    %w[password secret token key credential].each do |field|
      masked.each do |k, v|
        masked[k] = mask_value(v) if k.to_s.downcase.include?(field)
      end
    end

    masked
  end

  ##
  # Mask a sensitive value
  #
  # @param value [String] Value to mask
  # @return [String] Masked value
  def mask_value(value)
    return "[nil]" if value.nil?
    return "[empty]" if value.to_s.empty?

    str = value.to_s
    return str if str.length <= 8

    "#{str[0..3]}#{"*" * (str.length - 8)}#{str[-4..]}"
  end

  ##
  # Sanitize context for logging
  #
  # @param context [Hash] Context to sanitize
  # @return [Hash] Sanitized context
  def sanitize_context(context)
    context.reject { |k, _v| k.to_s.include?("password") || k.to_s.include?("secret") }
  end

  ##
  # Validate configuration
  def validate_configuration!
    valid_levels = %i[debug info warn error]
    return if valid_levels.include?(@log_level)

    raise ArgumentError, "Invalid log level: #{@log_level}. Must be one of: #{valid_levels.join(", ")}"
  end
end
