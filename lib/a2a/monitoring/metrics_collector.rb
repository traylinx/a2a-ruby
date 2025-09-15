# frozen_string_literal: true

require "monitor"

module A2A
  module Monitoring
  end
end

##
# Metrics collector for performance monitoring and alerting
#
# Collects and aggregates performance metrics, provides alerting capabilities,
# and integrates with monitoring systems like Prometheus, StatsD, etc.
#
module A2A
  module Monitoring
    class MetricsCollector
      include MonitorMixin

      # Metric types
      COUNTER = :counter
      GAUGE = :gauge
      HISTOGRAM = :histogram
      TIMER = :timer

      attr_reader :metrics, :start_time

      ##
      # Initialize metrics collector
      #
      # @param flush_interval [Integer] Interval to flush metrics (seconds)
      # @param retention_period [Integer] How long to keep metrics (seconds)
      def initialize(flush_interval: 60, retention_period: 3600)
        super()

        @metrics = {}
        @flush_interval = flush_interval
        @retention_period = retention_period
        @start_time = Time.now
        @last_flush = Time.now
        @exporters = []
        @alert_rules = []

        start_background_flush if flush_interval.positive?
      end

      ##
      # Increment a counter metric
      #
      # @param name [String] Metric name
      # @param value [Numeric] Value to add (default: 1)
      # @param tags [Hash] Metric tags
      def increment(name, value: 1, **tags)
        synchronize do
          metric = get_or_create_metric(name, COUNTER, tags)
          metric[:value] += value
          metric[:last_updated] = Time.now

          check_alerts(name, metric[:value], tags)
        end
      end

      ##
      # Set a gauge metric value
      #
      # @param name [String] Metric name
      # @param value [Numeric] Metric value
      # @param tags [Hash] Metric tags
      def gauge(name, value, **tags)
        synchronize do
          metric = get_or_create_metric(name, GAUGE, tags)
          metric[:value] = value
          metric[:last_updated] = Time.now

          check_alerts(name, value, tags)
        end
      end

      ##
      # Record a histogram value
      #
      # @param name [String] Metric name
      # @param value [Numeric] Value to record
      # @param tags [Hash] Metric tags
      def histogram(name, value, **tags)
        synchronize do
          metric = get_or_create_metric(name, HISTOGRAM, tags)
          metric[:values] << value
          metric[:count] += 1
          metric[:sum] += value
          metric[:last_updated] = Time.now

          # Calculate percentiles
          update_histogram_stats(metric)

          check_alerts(name, value, tags)
        end
      end

      ##
      # Time a block of code
      #
      # @param name [String] Metric name
      # @param tags [Hash] Metric tags
      # @yield Block to time
      # @return [Object] Result of the block
      def time(name, **tags)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        begin
          result = yield
          duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
          histogram("#{name}.duration", duration * 1000, **tags) # Convert to milliseconds
          increment("#{name}.success", **tags)
          result
        rescue StandardError
          duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
          histogram("#{name}.duration", duration * 1000, **tags)
          increment("#{name}.error", **tags)
          raise
        end
      end

      ##
      # Record HTTP request metrics
      #
      # @param method [String] HTTP method
      # @param path [String] Request path
      # @param status [Integer] Response status
      # @param duration [Float] Request duration in seconds
      # @param tags [Hash] Additional tags
      def http_request(method:, path:, status:, duration:, **tags)
        base_tags = {
          method: method.to_s.upcase,
          path: normalize_path(path),
          status: status,
          **tags
        }

        increment("http_requests_total", **base_tags)
        histogram("http_request_duration_ms", duration * 1000, **base_tags)

        # Track error rates
        return unless status >= 400

        increment("http_requests_errors_total", **base_tags)
      end

      ##
      # Record task metrics
      #
      # @param operation [String] Task operation
      # @param task_type [String] Type of task
      # @param status [String] Task status
      # @param duration [Float, nil] Operation duration
      # @param tags [Hash] Additional tags
      def task_operation(operation:, task_type: nil, status: nil, duration: nil, **tags)
        base_tags = {
          operation: operation,
          task_type: task_type,
          status: status,
          **tags
        }.compact

        increment("task_operations_total", **base_tags)

        return unless duration

        histogram("task_operation_duration_ms", duration * 1000, **base_tags)
      end

      ##
      # Add a metrics exporter
      #
      # @param exporter [Object] Exporter object with export(metrics) method
      def add_exporter(exporter)
        synchronize { @exporters << exporter }
      end

      ##
      # Remove a metrics exporter
      #
      # @param exporter [Object] Exporter to remove
      def remove_exporter(exporter)
        synchronize { @exporters.delete(exporter) }
      end

      ##
      # Add an alert rule
      #
      # @param name [String] Alert name
      # @param metric [String] Metric name to monitor
      # @param condition [Symbol] Condition (:gt, :lt, :eq, :gte, :lte)
      # @param threshold [Numeric] Threshold value
      # @param callback [Proc] Callback to execute when alert fires
      def add_alert(name, metric:, condition:, threshold:, &callback)
        synchronize do
          @alert_rules << {
            name: name,
            metric: metric,
            condition: condition,
            threshold: threshold,
            callback: callback,
            last_fired: nil
          }
        end
      end

      ##
      # Get current metrics snapshot
      #
      # @return [Hash] Current metrics
      def snapshot
        synchronize { deep_copy(@metrics) }
      end

      ##
      # Get metrics summary
      #
      # @return [Hash] Metrics summary
      def summary
        synchronize do
          {
            total_metrics: @metrics.size,
            uptime: Time.now - @start_time,
            last_flush: @last_flush,
            exporters: @exporters.size,
            alert_rules: @alert_rules.size,
            memory_usage: get_memory_usage
          }
        end
      end

      ##
      # Flush metrics to exporters
      #
      def flush!
        metrics_snapshot = snapshot

        @exporters.each do |exporter|
          exporter.export(metrics_snapshot)
        rescue StandardError => e
          warn "Failed to export metrics: #{e.message}"
        end

        synchronize { @last_flush = Time.now }
        cleanup_old_metrics
      end

      ##
      # Reset all metrics
      #
      def reset!
        synchronize do
          @metrics.clear
          @start_time = Time.now
          @last_flush = Time.now
        end
      end

      ##
      # Stop the metrics collector
      #
      def stop
        @flush_thread&.kill
        @flush_thread = nil
      end

      private

      ##
      # Get or create a metric
      #
      # @param name [String] Metric name
      # @param type [Symbol] Metric type
      # @param tags [Hash] Metric tags
      # @return [Hash] Metric data
      def get_or_create_metric(name, type, tags)
        key = build_metric_key(name, tags)

        @metrics[key] ||= {
          name: name,
          type: type,
          tags: tags,
          value: type == COUNTER ? 0 : nil,
          values: type == HISTOGRAM ? [] : nil,
          count: type == HISTOGRAM ? 0 : nil,
          sum: type == HISTOGRAM ? 0 : nil,
          created_at: Time.now,
          last_updated: Time.now
        }
      end

      ##
      # Build metric key from name and tags
      #
      # @param name [String] Metric name
      # @param tags [Hash] Metric tags
      # @return [String] Metric key
      def build_metric_key(name, tags)
        if tags.empty?
          name
        else
          tag_string = tags.sort.map { |k, v| "#{k}=#{v}" }.join(",")
          "#{name}{#{tag_string}}"
        end
      end

      ##
      # Update histogram statistics
      #
      # @param metric [Hash] Histogram metric
      def update_histogram_stats(metric)
        values = metric[:values].sort
        count = values.size

        return if count.zero?

        metric[:min] = values.first
        metric[:max] = values.last
        metric[:avg] = metric[:sum].to_f / count

        # Calculate percentiles
        metric[:p50] = percentile(values, 0.5)
        metric[:p95] = percentile(values, 0.95)
        metric[:p99] = percentile(values, 0.99)

        # Keep only recent values to prevent memory growth
        return unless values.size > 1000

        metric[:values] = values.last(1000)
      end

      ##
      # Calculate percentile from sorted values
      #
      # @param values [Array] Sorted array of values
      # @param percentile [Float] Percentile (0.0 to 1.0)
      # @return [Numeric] Percentile value
      def percentile(values, percentile)
        return 0 if values.empty?

        index = (percentile * (values.size - 1)).round
        values[index]
      end

      ##
      # Check alert rules
      #
      # @param metric_name [String] Metric name
      # @param value [Numeric] Metric value
      # @param tags [Hash] Metric tags
      def check_alerts(metric_name, value, tags)
        @alert_rules.each do |rule|
          next unless rule[:metric] == metric_name

          should_fire = case rule[:condition]
                        when :gt then value > rule[:threshold]
                        when :gte then value >= rule[:threshold]
                        when :lt then value < rule[:threshold]
                        when :lte then value <= rule[:threshold]
                        when :eq then value == rule[:threshold]
                        else false
                        end

          if should_fire && (rule[:last_fired].nil? || Time.now - rule[:last_fired] > 60)
            rule[:callback]&.call(rule[:name], metric_name, value, tags)
            rule[:last_fired] = Time.now
          end
        end
      end

      ##
      # Normalize URL path for metrics
      #
      # @param path [String] URL path
      # @return [String] Normalized path
      def normalize_path(path)
        # Replace IDs and UUIDs with placeholders
        path.gsub(%r{/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}}, "/:uuid")
            .gsub(%r{/\d+}, "/:id")
      end

      ##
      # Start background flush thread
      #
      def start_background_flush
        @flush_thread = Thread.new do
          loop do
            sleep @flush_interval
            flush!
          rescue StandardError => e
            warn "Error in metrics flush thread: #{e.message}"
          end
        end
      end

      ##
      # Clean up old metrics
      #
      def cleanup_old_metrics
        cutoff_time = Time.now - @retention_period

        synchronize do
          @metrics.reject! do |_, metric|
            metric[:last_updated] < cutoff_time
          end
        end
      end

      ##
      # Get current memory usage
      #
      # @return [Integer] Memory usage in bytes
      def get_memory_usage
        if defined?(GC.stat)
          GC.stat(:heap_allocated_pages) * GC.stat(:heap_page_size)
        else
          0
        end
      rescue StandardError
        0
      end

      ##
      # Deep copy a hash
      #
      # @param obj [Object] Object to copy
      # @return [Object] Deep copy
      def deep_copy(obj)
        Marshal.load(Marshal.dump(obj))
      rescue StandardError
        obj.dup
      end
    end
  end
end
