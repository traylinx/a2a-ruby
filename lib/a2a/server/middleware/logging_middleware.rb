# frozen_string_literal: true

require "logger"
require "json"

##
# Logging middleware for A2A requests
#
# Provides comprehensive logging for A2A requests and responses,
# including request/response tracking, performance metrics, and
# structured logging support.
#
# @example Basic usage
#   middleware = LoggingMiddleware.new(
#     logger: Rails.logger,
#     level: :info,
#     format: :structured
#   )
#
class A2A::Server::Middleware::LoggingMiddleware
  attr_accessor :logger
  attr_reader :level, :format, :options

  # Logging formats
  FORMATS = %i[simple detailed structured json].freeze

  ##
  # Initialize logging middleware
  #
  # @param logger [Logger] The logger instance to use
  # @param level [Symbol] The log level (:debug, :info, :warn, :error)
  # @param format [Symbol] The log format (:simple, :detailed, :structured, :json)
  # @param options [Hash] Additional logging options
  # @option options [Boolean] :log_params Whether to log request parameters
  # @option options [Boolean] :log_response Whether to log response data
  # @option options [Boolean] :log_errors Whether to log error details
  # @option options [Array<String>] :filtered_params Parameters to filter from logs
  def initialize(logger: nil, level: :info, format: :detailed, **options)
    @logger = logger || default_logger
    @level = level
    @format = format
    @options = {
      log_params: true,
      log_response: false,
      log_errors: true,
      filtered_params: %w[password token api_key secret],
      include_context: true,
      include_timing: true
    }.merge(options)

    validate_format!
  end

  ##
  # Process logging for a request
  #
  # @param request [A2A::Protocol::Request] The JSON-RPC request
  # @param context [A2A::Server::Context] The request context
  # @yield Block to continue the middleware chain
  # @return [Object] The result from the next middleware or handler
  def call(request, context)
    start_time = Time.zone.now
    request_id = generate_request_id(request, context)

    # Log request start
    log_request_start(request, context, request_id)

    begin
      # Execute next middleware/handler
      result = yield

      # Log successful completion
      duration = Time.zone.now - start_time
      log_request_success(request, context, result, duration, request_id)

      result
    rescue StandardError => e
      # Log error
      duration = Time.zone.now - start_time
      log_request_error(request, context, e, duration, request_id)

      # Re-raise the error
      raise
    end
  end

  ##
  # Set custom logger
  #
  # @param new_logger [Logger] The new logger instance

  ##
  # Add filtered parameter
  #
  # @param param [String] Parameter name to filter
  def add_filtered_param(param)
    @options[:filtered_params] << param.to_s
  end

  ##
  # Remove filtered parameter
  #
  # @param param [String] Parameter name to unfilter
  def remove_filtered_param(param)
    @options[:filtered_params].delete(param.to_s)
  end

  private

  ##
  # Validate the logging format
  def validate_format!
    return if FORMATS.include?(@format)

    raise ArgumentError, "Invalid format: #{@format}. Must be one of: #{FORMATS.join(", ")}"
  end

  ##
  # Get default logger
  def default_logger
    if defined?(Rails) && Rails.logger
      Rails.logger
    else
      Logger.new($stdout).tap do |logger|
        logger.level = Logger::INFO
      end
    end
  end

  ##
  # Generate a unique request ID
  #
  # @param request [A2A::Protocol::Request] The request
  # @param context [A2A::Server::Context] The context
  # @return [String] The request ID
  def generate_request_id(request, _context)
    # Use existing request ID if available
    return request.id.to_s if request.id

    # Generate a new ID
    "req_#{Time.now.to_f}_#{rand(10_000)}"
  end

  ##
  # Log request start
  #
  # @param request [A2A::Protocol::Request] The request
  # @param context [A2A::Server::Context] The context
  # @param request_id [String] The request ID
  def log_request_start(request, context, request_id)
    case @format
    when :simple
      @logger.send(@level, "A2A Request: #{request.method}")
    when :detailed
      log_detailed_start(request, context, request_id)
    when :structured
      log_structured_start(request, context, request_id)
    when :json
      log_json_start(request, context, request_id)
    end
  end

  ##
  # Log successful request completion
  #
  # @param request [A2A::Protocol::Request] The request
  # @param context [A2A::Server::Context] The context
  # @param result [Object] The response result
  # @param duration [Float] Request duration in seconds
  # @param request_id [String] The request ID
  def log_request_success(request, context, result, duration, request_id)
    case @format
    when :simple
      @logger.send(@level, "A2A Response: #{request.method} (#{duration.round(3)}s)")
    when :detailed
      log_detailed_success(request, context, result, duration, request_id)
    when :structured
      log_structured_success(request, context, result, duration, request_id)
    when :json
      log_json_success(request, context, result, duration, request_id)
    end
  end

  ##
  # Log request error
  #
  # @param request [A2A::Protocol::Request] The request
  # @param context [A2A::Server::Context] The context
  # @param error [StandardError] The error
  # @param duration [Float] Request duration in seconds
  # @param request_id [String] The request ID
  def log_request_error(request, context, error, duration, request_id)
    case @format
    when :simple
      @logger.error("A2A Error: #{request.method} - #{error.class.name}: #{error.message}")
    when :detailed
      log_detailed_error(request, context, error, duration, request_id)
    when :structured
      log_structured_error(request, context, error, duration, request_id)
    when :json
      log_json_error(request, context, error, duration, request_id)
    end
  end

  ##
  # Log detailed request start
  def log_detailed_start(request, context, request_id)
    message = "A2A Request Started - Method: #{request.method}, ID: #{request_id}"

    if @options[:log_params] && !request.params.empty?
      filtered_params = filter_sensitive_data(request.params)
      message += ", Params: #{filtered_params.inspect}"
    end

    message += ", Authenticated: true" if @options[:include_context] && context.authenticated?

    @logger.send(@level, message)
  end

  ##
  # Log detailed request success
  def log_detailed_success(request, _context, result, duration, request_id)
    message = "A2A Request Completed - Method: #{request.method}, ID: #{request_id}, Duration: #{duration.round(3)}s"

    if @options[:log_response] && result
      filtered_result = filter_sensitive_data(result)
      message += ", Response: #{filtered_result.inspect}"
    end

    @logger.send(@level, message)
  end

  ##
  # Log detailed request error
  def log_detailed_error(request, _context, error, duration, request_id)
    message = "A2A Request Failed - Method: #{request.method}, ID: #{request_id}, Duration: #{duration.round(3)}s"
    message += ", Error: #{error.class.name}: #{error.message}"

    if @options[:log_errors] && error.respond_to?(:backtrace) && error.backtrace
      message += ", Backtrace: #{error.backtrace.first(3).join(" | ")}"
    end

    @logger.error(message)
  end

  ##
  # Log structured request start
  def log_structured_start(request, context, request_id)
    data = {
      event: "a2a_request_start",
      method: request.method,
      request_id: request_id,
      timestamp: Time.now.iso8601
    }

    data[:params] = filter_sensitive_data(request.params) if @options[:log_params] && !request.params.empty?

    if @options[:include_context]
      data[:authenticated] = context.authenticated?
      data[:user] = context.user if context.user
    end

    @logger.send(@level, format_structured_log(data))
  end

  ##
  # Log structured request success
  def log_structured_success(request, _context, result, duration, request_id)
    data = {
      event: "a2a_request_success",
      method: request.method,
      request_id: request_id,
      duration: duration.round(3),
      timestamp: Time.now.iso8601
    }

    data[:response] = filter_sensitive_data(result) if @options[:log_response] && result

    @logger.send(@level, format_structured_log(data))
  end

  ##
  # Log structured request error
  def log_structured_error(request, _context, error, duration, request_id)
    data = {
      event: "a2a_request_error",
      method: request.method,
      request_id: request_id,
      duration: duration.round(3),
      error_class: error.class.name,
      error_message: error.message,
      timestamp: Time.now.iso8601
    }

    if @options[:log_errors] && error.respond_to?(:backtrace) && error.backtrace
      data[:backtrace] = error.backtrace.first(5)
    end

    data[:error_code] = error.code if error.respond_to?(:code)

    @logger.error(format_structured_log(data))
  end

  ##
  # Log JSON format (same as structured but always JSON)
  def log_json_start(request, context, request_id)
    log_structured_start(request, context, request_id)
  end

  def log_json_success(request, context, result, duration, request_id)
    log_structured_success(request, context, result, duration, request_id)
  end

  def log_json_error(request, context, error, duration, request_id)
    log_structured_error(request, context, error, duration, request_id)
  end

  ##
  # Format structured log data
  #
  # @param data [Hash] The log data
  # @return [String] Formatted log message
  def format_structured_log(data)
    if @format == :json
      JSON.generate(data)
    else
      # Key=value format for structured logs
      data.map { |k, v| "#{k}=#{v.inspect}" }.join(" ")
    end
  end

  ##
  # Filter sensitive data from parameters/responses
  #
  # @param data [Object] The data to filter
  # @return [Object] Filtered data
  def filter_sensitive_data(data)
    case data
    when Hash
      filtered = {}
      data.each do |key, value|
        filtered[key] = if @options[:filtered_params].include?(key.to_s.downcase)
                          "[FILTERED]"
                        else
                          filter_sensitive_data(value)
                        end
      end
      filtered
    when Array
      data.map { |item| filter_sensitive_data(item) }
    else
      data
    end
  end
end
