# frozen_string_literal: true

require "logger"
require "json"
require "securerandom"

##
# Structured logger for A2A operations
#
# Provides structured logging with correlation IDs, performance metrics,
# and integration with monitoring systems.
#
class A2A::Utils::StructuredLogger
  # Log levels
  LEVELS = {
    debug: Logger::DEBUG,
    info: Logger::INFO,
    warn: Logger::WARN,
    error: Logger::ERROR,
    fatal: Logger::FATAL
  }.freeze

  attr_accessor :correlation_id
  attr_reader :logger, :service_name, :version

  ##
  # Initialize structured logger
  #
  # @param output [IO, String] Output destination (IO object or file path)
  # @param level [Symbol, Integer] Log level
  # @param service_name [String] Name of the service
  # @param version [String] Version of the service
  # @param correlation_id [String, nil] Correlation ID for request tracking
  def initialize(output: $stdout, level: :info, service_name: "a2a-ruby", version: A2A::VERSION,
    correlation_id: nil)
    @logger = Logger.new(output)
    @logger.level = LEVELS[level] || level
    @logger.formatter = method(:format_log_entry)
    @service_name = service_name
    @version = version
    @correlation_id = correlation_id || generate_correlation_id
    @start_time = Time.now
  end

  ##
  # Log a debug message
  #
  # @param message [String] Log message
  # @param context [Hash] Additional context
  def debug(message, **context)
    log(:debug, message, **context)
  end

  ##
  # Log an info message
  #
  # @param message [String] Log message
  # @param context [Hash] Additional context
  def info(message, **context)
    log(:info, message, **context)
  end

  ##
  # Log a warning message
  #
  # @param message [String] Log message
  # @param context [Hash] Additional context
  def warn(message, **context)
    log(:warn, message, **context)
  end

  ##
  # Log an error message
  #
  # @param message [String] Log message
  # @param error [Exception, nil] Exception object
  # @param context [Hash] Additional context
  def error(message, error: nil, **context)
    context[:error] = format_error(error) if error
    log(:error, message, **context)
  end

  ##
  # Log a fatal message
  #
  # @param message [String] Log message
  # @param error [Exception, nil] Exception object
  # @param context [Hash] Additional context
  def fatal(message, error: nil, **context)
    context[:error] = format_error(error) if error
    log(:fatal, message, **context)
  end

  ##
  # Log with timing information
  #
  # @param message [String] Log message
  # @param level [Symbol] Log level
  # @param context [Hash] Additional context
  # @yield Block to time
  # @return [Object] Result of the block
  def timed(message, level: :info, **context)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    begin
      result = yield
      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      log(level, "#{message} completed", duration: duration, **context)
      result
    rescue StandardError => e
      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      error("#{message} failed",
        error: e,
        duration: duration,
        **context)
      raise
    end
  end

  ##
  # Log HTTP request/response
  #
  # @param method [String] HTTP method
  # @param url [String] Request URL
  # @param status [Integer] Response status
  # @param duration [Float] Request duration
  # @param context [Hash] Additional context
  def http_request(method:, url:, status:, duration:, **context)
    log_data = {
      http_method: method.to_s.upcase,
      url: url,
      status_code: status,
      duration: duration,
      **context
    }

    level = case status
            when 200..299 then :info
            when 300..399 then :info
            when 400..499 then :warn
            when 500..599 then :error
            else :info
            end

    log(level, "HTTP #{method.upcase} #{url}", **log_data)
  end

  ##
  # Log task operation
  #
  # @param operation [String] Task operation (create, update, cancel, etc.)
  # @param task_id [String] Task ID
  # @param context_id [String, nil] Context ID
  # @param status [String, nil] Task status
  # @param context [Hash] Additional context
  def task_operation(operation:, task_id:, context_id: nil, status: nil, **context)
    log_data = {
      operation: operation,
      task_id: task_id,
      context_id: context_id,
      task_status: status,
      **context
    }.compact

    log(:info, "Task #{operation}", **log_data)
  end

  ##
  # Log performance metrics
  #
  # @param metric_name [String] Name of the metric
  # @param value [Numeric] Metric value
  # @param unit [String] Unit of measurement
  # @param tags [Hash] Metric tags
  def metric(metric_name, value, unit: nil, **tags)
    log_data = {
      metric_name: metric_name,
      metric_value: value,
      metric_unit: unit,
      metric_tags: tags
    }.compact

    log(:info, "Metric: #{metric_name}", **log_data)
  end

  ##
  # Create a child logger with additional context
  #
  # @param context [Hash] Additional context to include in all log entries
  # @return [StructuredLogger] Child logger
  def child(**context)
    child_logger = self.class.new(
      output: @logger.instance_variable_get(:@logdev).dev,
      level: @logger.level,
      service_name: @service_name,
      version: @version,
      correlation_id: @correlation_id
    )

    child_logger.instance_variable_set(:@additional_context, context)
    child_logger
  end

  ##
  # Set correlation ID for request tracking
  #
  # @param correlation_id [String] Correlation ID

  ##
  # Generate a new correlation ID
  #
  # @return [String] New correlation ID
  def generate_correlation_id
    SecureRandom.hex(8)
  end

  ##
  # Get logger statistics
  #
  # @return [Hash] Logger statistics
  def stats
    {
      service_name: @service_name,
      version: @version,
      correlation_id: @correlation_id,
      uptime: Time.now - @start_time,
      log_level: @logger.level
    }
  end

  private

  ##
  # Log a message with structured data
  #
  # @param level [Symbol] Log level
  # @param message [String] Log message
  # @param context [Hash] Additional context
  def log(level, message, **context)
    return unless @logger.public_send("#{level}?")

    # Merge additional context from child loggers
    additional_context = instance_variable_get(:@additional_context) || {}
    context = additional_context.merge(context)

    log_entry = build_log_entry(level, message, **context)
    @logger.public_send(level, log_entry)
  end

  ##
  # Build structured log entry
  #
  # @param level [Symbol] Log level
  # @param message [String] Log message
  # @param context [Hash] Additional context
  # @return [Hash] Structured log entry
  def build_log_entry(level, message, **context)
    {
      timestamp: Time.now.utc.iso8601(3),
      level: level.to_s.upcase,
      message: message,
      service: @service_name,
      version: @version,
      correlation_id: @correlation_id,
      thread_id: Thread.current.object_id,
      **context
    }
  end

  ##
  # Format log entry for output
  #
  # @param severity [String] Log severity
  # @param datetime [Time] Log timestamp
  # @param progname [String] Program name
  # @param msg [Hash] Log message data
  # @return [String] Formatted log entry
  def format_log_entry(severity, _datetime, _progname, msg)
    if msg.is_a?(Hash)
      "#{JSON.generate(msg)}\n"
    else
      # Fallback for non-structured messages
      entry = build_log_entry(severity.downcase.to_sym, msg.to_s)
      "#{JSON.generate(entry)}\n"
    end
  end

  ##
  # Format error information
  #
  # @param error [Exception] Exception object
  # @return [Hash] Formatted error information
  def format_error(error)
    {
      class: error.class.name,
      message: error.message,
      backtrace: error.backtrace&.first(10) # Limit backtrace length
    }
  end
end
