# frozen_string_literal: true

require "logger"
require "json"
require_relative "monitoring/metrics_collector"
require_relative "monitoring/distributed_tracing"
require_relative "monitoring/alerting"

##
# Monitoring and metrics collection for A2A SDK
#
# Provides structured logging, metrics collection, and health checks
# with support for multiple backends including Prometheus.
#
module A2A::Monitoring
  class << self
    # Global metrics collector
    # @return [A2A::Monitoring::MetricsCollector]
    attr_accessor :metrics

    # Global logger with correlation ID support
    # @return [A2A::Monitoring::StructuredLogger]
    attr_accessor :logger

    # Initialize monitoring system
    # @param config [A2A::Configuration] Configuration instance
    def initialize!(config = A2A.config)
      @config = config
      @metrics = MetricsCollector.new(config)
      @logger = StructuredLogger.new(config)
      @health_checks = HealthChecker.new(config)
    end

    # Get metrics collector
    # @return [A2A::Monitoring::MetricsCollector]
    def metrics
      @metrics ||= MetricsCollector.new(A2A.config)
    end

    # Get structured logger
    # @return [A2A::Monitoring::StructuredLogger]
    def logger
      @logger ||= StructuredLogger.new(A2A.config)
    end

    # Get health checker
    # @return [A2A::Monitoring::HealthChecker]
    def health_checks
      @health_checks ||= HealthChecker.new(A2A.config)
    end

    # Record a metric
    # @param name [String] Metric name
    # @param value [Numeric] Metric value
    # @param **labels [Hash] Metric labels
    def record_metric(name, value, **labels)
      metrics.record(name, value, **labels)
    end

    # Increment a counter
    # @param name [String] Counter name
    # @param **labels [Hash] Counter labels
    def increment_counter(name, **labels)
      metrics.increment(name, **labels)
    end

    # Record timing information
    # @param name [String] Timer name
    # @param duration [Numeric] Duration in seconds
    # @param **labels [Hash] Timer labels
    def record_timing(name, duration, **labels)
      metrics.timing(name, duration, **labels)
    end

    # Time a block of code
    # @param name [String] Timer name
    # @param **labels [Hash] Timer labels
    # @yield Block to time
    # @return [Object] Block result
    def time(name, **labels)
      start_time = Time.current
      result = yield
      duration = Time.current - start_time
      record_timing(name, duration, **labels)
      result
    rescue StandardError
      duration = Time.current - start_time
      record_timing(name, duration, status: "error", **labels)
      raise
    end

    # Log with correlation ID
    # @param level [Symbol] Log level
    # @param message [String] Log message
    # @param **context [Hash] Additional context
    def log(level, message, **context)
      logger.log(level, message, **context)
    end
  end

  ##
  # Metrics collection interface
  #
  class MetricsCollector
    # Initialize metrics collector
    # @param config [A2A::Configuration] Configuration instance
    def initialize(config)
      @config = config
      @backends = []
      @metrics_buffer = []
      @mutex = Mutex.new

      setup_backends
    end

    # Record a metric
    # @param name [String] Metric name
    # @param value [Numeric] Metric value
    # @param **labels [Hash] Metric labels
    def record(name, value, **labels)
      metric = {
        name: name,
        value: value,
        labels: labels,
        timestamp: Time.current.to_f
      }

      @mutex.synchronize do
        @metrics_buffer << metric
        flush_if_needed
      end

      @backends.each { |backend| backend.record(name, value, **labels) }
    end

    # Increment a counter
    # @param name [String] Counter name
    # @param **labels [Hash] Counter labels
    def increment(name, **labels)
      record("#{name}_total", 1, **labels)
    end

    # Record timing information
    # @param name [String] Timer name
    # @param duration [Numeric] Duration in seconds
    # @param **labels [Hash] Timer labels
    def timing(name, duration, **labels)
      record("#{name}_duration_seconds", duration, **labels)
    end

    # Add metrics backend
    # @param backend [Object] Metrics backend
    def add_backend(backend)
      @backends << backend
    end

    # Get current metrics
    # @return [Array<Hash>] Current metrics buffer
    def current_metrics
      @mutex.synchronize { @metrics_buffer.dup }
    end

    # Flush metrics buffer
    def flush!
      @mutex.synchronize do
        @metrics_buffer.clear
      end
    end

    private

    def setup_backends
      # Add Prometheus backend if available
      add_backend(PrometheusBackend.new) if defined?(Prometheus)

      # Add logging backend
      add_backend(LoggingBackend.new(@config))
    end

    def flush_if_needed
      return unless @metrics_buffer.size >= 100

      # In a real implementation, you might want to flush to persistent storage
      @config.logger&.debug("Metrics buffer size: #{@metrics_buffer.size}")
    end
  end

  ##
  # Structured logger with correlation ID support
  #
  class StructuredLogger
    # Initialize structured logger
    # @param config [A2A::Configuration] Configuration instance
    def initialize(config)
      @config = config
      @base_logger = config.logger
      @correlation_ids = {}
    end

    # Log with structured format
    # @param level [Symbol] Log level
    # @param message [String] Log message
    # @param **context [Hash] Additional context
    def log(level, message, **context)
      return unless @base_logger

      correlation_id = current_correlation_id

      structured_data = {
        timestamp: Time.current.iso8601,
        level: level.to_s.upcase,
        message: message,
        correlation_id: correlation_id,
        component: "a2a-ruby"
      }.merge(context)

      @base_logger.send(level, structured_data.to_json)
    end

    # Set correlation ID for current thread
    # @param id [String] Correlation ID
    def set_correlation_id(id)
      @correlation_ids[Thread.current.object_id] = id
    end

    # Get correlation ID for current thread
    # @return [String] Correlation ID
    def current_correlation_id
      @correlation_ids[Thread.current.object_id] || generate_correlation_id
    end

    # Clear correlation ID for current thread
    def clear_correlation_id
      @correlation_ids.delete(Thread.current.object_id)
    end

    # Execute block with correlation ID
    # @param id [String] Correlation ID
    # @yield Block to execute
    # @return [Object] Block result
    def with_correlation_id(id)
      old_id = current_correlation_id
      set_correlation_id(id)
      yield
    ensure
      if old_id
        set_correlation_id(old_id)
      else
        clear_correlation_id
      end
    end

    private

    def generate_correlation_id
      SecureRandom.hex(8)
    end
  end

  ##
  # Health check system
  #
  class HealthChecker
    # Initialize health checker
    # @param config [A2A::Configuration] Configuration instance
    def initialize(config)
      @config = config
      @checks = {}
    end

    # Register a health check
    # @param name [Symbol] Check name
    # @param check [Proc] Check procedure
    def register_check(name, &check)
      @checks[name] = check
    end

    # Run all health checks
    # @return [Hash] Health check results
    def check_health
      results = {}
      overall_status = :healthy

      @checks.each do |name, check|
        result = check.call
        status = result[:status] || :healthy
        results[name] = {
          status: status,
          message: result[:message],
          timestamp: Time.current.iso8601
        }

        overall_status = :unhealthy if status == :unhealthy
      rescue StandardError => e
        results[name] = {
          status: :error,
          message: e.message,
          timestamp: Time.current.iso8601
        }
        overall_status = :unhealthy
      end

      {
        status: overall_status,
        checks: results,
        timestamp: Time.current.iso8601
      }
    end

    # Check if system is healthy
    # @return [Boolean]
    def healthy?
      check_health[:status] == :healthy
    end
  end

  ##
  # Prometheus metrics backend
  #
  class PrometheusBackend
    def initialize
      @registry = Prometheus::Client.registry
      @counters = {}
      @histograms = {}
    end

    # Record metric in Prometheus
    # @param name [String] Metric name
    # @param value [Numeric] Metric value
    # @param **labels [Hash] Metric labels
    def record(name, value, **labels)
      if name.end_with?("_total")
        increment_counter(name, **labels)
      elsif name.end_with?("_duration_seconds")
        record_histogram(name, value, **labels)
      else
        # Generic gauge
        record_gauge(name, value, **labels)
      end
    end

    private

    def increment_counter(name, **labels)
      counter = @counters[name] ||= @registry.counter(
        name.to_sym,
        docstring: "A2A counter: #{name}",
        labels: labels.keys
      )
      counter.increment(labels: labels)
    end

    def record_histogram(name, value, **labels)
      histogram = @histograms[name] ||= @registry.histogram(
        name.to_sym,
        docstring: "A2A histogram: #{name}",
        labels: labels.keys
      )
      histogram.observe(value, labels: labels)
    end

    def record_gauge(name, value, **labels)
      # Prometheus gauge implementation would go here
      # For now, just log it
    end
  end

  ##
  # Logging metrics backend
  #
  class LoggingBackend
    def initialize(config)
      @config = config
      @logger = config.logger
    end

    # Record metric to logs
    # @param name [String] Metric name
    # @param value [Numeric] Metric value
    # @param **labels [Hash] Metric labels
    def record(name, value, **labels)
      return unless @logger

      metric_data = {
        metric_name: name,
        metric_value: value,
        metric_labels: labels,
        timestamp: Time.current.iso8601
      }

      @logger.info("METRIC: #{metric_data.to_json}")
    end
  end

  ##
  # Request/Response instrumentation
  #
  module Instrumentation
    # Instrument A2A request
    # @param request [Hash] Request data
    # @yield Block to execute
    # @return [Object] Block result
    def self.instrument_request(request)
      method = request[:method] || "unknown"
      labels = { method: method }

      A2A::Monitoring.increment_counter("a2a_requests", **labels)

      A2A::Monitoring.time("a2a_request_duration", **labels) do
        correlation_id = request[:id] || SecureRandom.hex(8)

        A2A::Monitoring.logger.with_correlation_id(correlation_id) do
          A2A::Monitoring.log(:info, "Processing A2A request", method: method, request_id: correlation_id)

          begin
            result = yield
            A2A::Monitoring.increment_counter("a2a_requests_success", **labels)
            A2A::Monitoring.log(:info, "A2A request completed", method: method, request_id: correlation_id)
            result
          rescue StandardError => e
            A2A::Monitoring.increment_counter("a2a_requests_error", **labels, error_type: e.class.name)
            A2A::Monitoring.log(:error, "A2A request failed", method: method, request_id: correlation_id,
              error: e.message)
            raise
          end
        end
      end
    end

    # Instrument task operations
    # @param task_id [String] Task ID
    # @param operation [String] Operation name
    # @yield Block to execute
    # @return [Object] Block result
    def self.instrument_task(task_id, operation)
      labels = { operation: operation }

      A2A::Monitoring.increment_counter("a2a_task_operations", **labels)

      A2A::Monitoring.time("a2a_task_operation_duration", **labels) do
        A2A::Monitoring.logger.with_correlation_id(task_id) do
          A2A::Monitoring.log(:info, "Task operation started", task_id: task_id, operation: operation)

          begin
            result = yield
            A2A::Monitoring.increment_counter("a2a_task_operations_success", **labels)
            A2A::Monitoring.log(:info, "Task operation completed", task_id: task_id, operation: operation)
            result
          rescue StandardError => e
            A2A::Monitoring.increment_counter("a2a_task_operations_error",
**labels, error_type: e.class.name)
            A2A::Monitoring.log(:error, "Task operation failed", task_id: task_id, operation: operation,
              error: e.message)
            raise
          end
        end
      end
    end
  end
end
