# frozen_string_literal: true

require "net/http"
require "json"

module A2A::Monitoring
  ##
  # Alerting system for A2A monitoring
  #
  # Provides configurable alerting based on metrics thresholds,
  # error rates, and system health indicators.
  #
  class Alerting
    # Alert severities
    SEVERITY_INFO = :info
    SEVERITY_WARNING = :warning
    SEVERITY_ERROR = :error
    SEVERITY_CRITICAL = :critical

    # Alert states
    STATE_FIRING = :firing
    STATE_RESOLVED = :resolved

    attr_reader :rules, :channels, :active_alerts

    ##
    # Initialize alerting system
    #
    # @param config [Hash] Alerting configuration
    def initialize(config = {})
      @rules = []
      @channels = []
      @active_alerts = {}
      @config = default_config.merge(config)
      @mutex = Mutex.new
    end

    ##
    # Add an alert rule
    #
    # @param name [String] Rule name
    # @param metric [String] Metric to monitor
    # @param condition [Hash] Alert condition
    # @param severity [Symbol] Alert severity
    # @param description [String] Alert description
    # @param tags [Hash] Additional tags
    def add_rule(name:, metric:, condition:, severity: SEVERITY_WARNING, description: nil, **tags)
      rule = {
        name: name,
        metric: metric,
        condition: condition,
        severity: severity,
        description: description || "Alert for #{metric}",
        tags: tags,
        created_at: Time.zone.now,
        last_evaluated: nil,
        evaluation_count: 0
      }

      @mutex.synchronize { @rules << rule }
    end

    ##
    # Add an alert channel
    #
    # @param channel [Object] Alert channel (webhook, email, etc.)
    def add_channel(channel)
      @mutex.synchronize { @channels << channel }
    end

    ##
    # Evaluate all alert rules against current metrics
    #
    # @param metrics [Hash] Current metrics snapshot
    def evaluate_rules(metrics)
      @mutex.synchronize do
        @rules.each do |rule|
          evaluate_rule(rule, metrics)
        end
      end
    end

    ##
    # Get active alerts
    #
    # @return [Array<Hash>] Active alerts
    def get_active_alerts
      @mutex.synchronize { @active_alerts.values.dup }
    end

    ##
    # Get alert statistics
    #
    # @return [Hash] Alert statistics
    def statistics
      @mutex.synchronize do
        {
          total_rules: @rules.size,
          active_alerts: @active_alerts.size,
          total_channels: @channels.size,
          alerts_by_severity: count_alerts_by_severity,
          evaluation_stats: get_evaluation_stats
        }
      end
    end

    ##
    # Clear resolved alerts older than specified time
    #
    # @param max_age [Integer] Maximum age in seconds (default: 1 hour)
    def cleanup_resolved_alerts(max_age: 3600)
      cutoff_time = Time.zone.now - max_age

      @mutex.synchronize do
        @active_alerts.reject! do |_, alert|
          alert[:state] == STATE_RESOLVED && alert[:resolved_at] < cutoff_time
        end
      end
    end

    private

    ##
    # Default configuration
    #
    # @return [Hash] Default configuration
    def default_config
      {
        evaluation_interval: 60,
        alert_timeout: 300,
        max_alerts: 1000
      }
    end

    ##
    # Evaluate a single alert rule
    #
    # @param rule [Hash] Alert rule
    # @param metrics [Hash] Current metrics
    def evaluate_rule(rule, metrics)
      rule[:last_evaluated] = Time.zone.now
      rule[:evaluation_count] += 1

      # Find matching metrics
      matching_metrics = find_matching_metrics(rule[:metric], metrics)

      matching_metrics.each do |metric_key, metric_data|
        evaluate_metric_against_rule(rule, metric_key, metric_data)
      end
    end

    ##
    # Find metrics matching the rule pattern
    #
    # @param pattern [String] Metric pattern
    # @param metrics [Hash] All metrics
    # @return [Hash] Matching metrics
    def find_matching_metrics(pattern, metrics)
      if pattern.include?("*")
        # Pattern matching
        regex = Regexp.new(pattern.gsub("*", ".*"))
        metrics.select { |key, _| key.match?(regex) }
      else
        # Exact match
        metric_data = metrics[pattern]
        metric_data ? { pattern => metric_data } : {}
      end
    end

    ##
    # Evaluate a specific metric against a rule
    #
    # @param rule [Hash] Alert rule
    # @param metric_key [String] Metric key
    # @param metric_data [Hash] Metric data
    def evaluate_metric_against_rule(rule, metric_key, metric_data)
      alert_key = "#{rule[:name]}_#{metric_key}"
      condition = rule[:condition]

      # Extract value based on metric type
      value = extract_metric_value(metric_data, condition[:field])
      return unless value

      # Evaluate condition
      should_fire = evaluate_condition(condition, value)

      if should_fire
        fire_alert(alert_key, rule, metric_key, value)
      else
        resolve_alert(alert_key)
      end
    end

    ##
    # Extract value from metric data
    #
    # @param metric_data [Hash] Metric data
    # @param field [String, nil] Specific field to extract
    # @return [Numeric, nil] Extracted value
    def extract_metric_value(metric_data, field = nil)
      case metric_data[:type]
      when :counter, :gauge
        metric_data[:value]
      when :histogram
        case field
        when "avg", "average" then metric_data[:avg]
        when "p95" then metric_data[:p95]
        when "p99" then metric_data[:p99]
        when "max" then metric_data[:max]
        when "min" then metric_data[:min]
        when "count" then metric_data[:count]
        else metric_data[:avg] # Default to average
        end
      else
        metric_data[:value]
      end
    end

    ##
    # Evaluate alert condition
    #
    # @param condition [Hash] Alert condition
    # @param value [Numeric] Current value
    # @return [Boolean] Whether condition is met
    def evaluate_condition(condition, value)
      operator = condition[:operator] || condition[:op]
      threshold = condition[:threshold]

      case operator.to_s
      when "gt", ">" then value > threshold
      when "gte", ">=" then value >= threshold
      when "lt", "<" then value < threshold
      when "lte", "<=" then value <= threshold
      when "eq", "==" then value == threshold
      when "ne", "!=" then value != threshold
      else false
      end
    end

    ##
    # Fire an alert
    #
    # @param alert_key [String] Alert key
    # @param rule [Hash] Alert rule
    # @param metric_key [String] Metric key
    # @param value [Numeric] Current value
    def fire_alert(alert_key, rule, metric_key, value)
      existing_alert = @active_alerts[alert_key]

      # Don't fire if already active and within timeout
      if existing_alert && existing_alert[:state] == STATE_FIRING
        time_since_fired = Time.zone.now - existing_alert[:fired_at]
        return if time_since_fired < @config[:alert_timeout]
      end

      alert = {
        key: alert_key,
        rule_name: rule[:name],
        metric: metric_key,
        value: value,
        condition: rule[:condition],
        severity: rule[:severity],
        description: rule[:description],
        tags: rule[:tags],
        state: STATE_FIRING,
        fired_at: Time.zone.now,
        resolved_at: nil
      }

      @active_alerts[alert_key] = alert
      send_alert_notification(alert)
    end

    ##
    # Resolve an alert
    #
    # @param alert_key [String] Alert key
    def resolve_alert(alert_key)
      alert = @active_alerts[alert_key]
      return unless alert && alert[:state] == STATE_FIRING

      alert[:state] = STATE_RESOLVED
      alert[:resolved_at] = Time.zone.now

      send_alert_notification(alert)
    end

    ##
    # Send alert notification to all channels
    #
    # @param alert [Hash] Alert data
    def send_alert_notification(alert)
      @channels.each do |channel|
        channel.send_alert(alert)
      rescue StandardError => e
        warn "Failed to send alert via #{channel.class}: #{e.message}"
      end
    end

    ##
    # Count alerts by severity
    #
    # @return [Hash] Alert counts by severity
    def count_alerts_by_severity
      counts = Hash.new(0)

      @active_alerts.each_value do |alert|
        next unless alert[:state] == STATE_FIRING

        counts[alert[:severity]] += 1
      end

      counts
    end

    ##
    # Get evaluation statistics
    #
    # @return [Hash] Evaluation statistics
    def get_evaluation_stats
      return {} if @rules.empty?

      total_evaluations = @rules.sum { |rule| rule[:evaluation_count] }
      avg_evaluations = total_evaluations.to_f / @rules.size

      {
        total_evaluations: total_evaluations,
        average_evaluations_per_rule: avg_evaluations,
        last_evaluation: @rules.pluck(:last_evaluated).compact.max
      }
    end
  end

  ##
  # Webhook alert channel
  #
  class WebhookAlertChannel
    attr_reader :url, :headers

    ##
    # Initialize webhook channel
    #
    # @param url [String] Webhook URL
    # @param headers [Hash] HTTP headers
    # @param timeout [Integer] Request timeout
    def initialize(url, headers: {}, timeout: 10)
      @url = url
      @headers = headers
      @timeout = timeout
    end

    ##
    # Send alert via webhook
    #
    # @param alert [Hash] Alert data
    def send_alert(alert)
      payload = format_alert_payload(alert)

      uri = URI(@url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.read_timeout = @timeout

      request = Net::HTTP::Post.new(uri.path)
      request["Content-Type"] = "application/json"
      @headers.each { |key, value| request[key] = value }
      request.body = payload.to_json

      response = http.request(request)

      return if response.is_a?(Net::HTTPSuccess)

      raise "Webhook request failed: #{response.code} #{response.message}"
    end

    private

    ##
    # Format alert for webhook payload
    #
    # @param alert [Hash] Alert data
    # @return [Hash] Formatted payload
    def format_alert_payload(alert)
      {
        alert_name: alert[:rule_name],
        metric: alert[:metric],
        value: alert[:value],
        severity: alert[:severity],
        state: alert[:state],
        description: alert[:description],
        fired_at: alert[:fired_at]&.iso8601,
        resolved_at: alert[:resolved_at]&.iso8601,
        tags: alert[:tags]
      }
    end
  end

  ##
  # Slack alert channel
  #
  class SlackAlertChannel
    ##
    # Initialize Slack channel
    #
    # @param webhook_url [String] Slack webhook URL
    # @param channel [String, nil] Slack channel name
    # @param username [String] Bot username
    def initialize(webhook_url, channel: nil, username: "A2A Alerts")
      @webhook_url = webhook_url
      @channel = channel
      @username = username
    end

    ##
    # Send alert to Slack
    #
    # @param alert [Hash] Alert data
    def send_alert(alert)
      payload = {
        username: @username,
        channel: @channel,
        attachments: [format_slack_attachment(alert)]
      }.compact

      uri = URI(@webhook_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri.path)
      request["Content-Type"] = "application/json"
      request.body = payload.to_json

      response = http.request(request)

      return if response.is_a?(Net::HTTPSuccess)

      raise "Slack webhook request failed: #{response.code}"
    end

    private

    ##
    # Format alert as Slack attachment
    #
    # @param alert [Hash] Alert data
    # @return [Hash] Slack attachment
    def format_slack_attachment(alert)
      color = case alert[:severity]
              when :critical then "danger"
              when :error then "danger"
              when :warning then "warning"
              else "good"
              end

      color = "good" if alert[:state] == :resolved

      {
        color: color,
        title: "#{alert[:state].to_s.capitalize}: #{alert[:rule_name]}",
        text: alert[:description],
        fields: [
          {
            title: "Metric",
            value: alert[:metric],
            short: true
          },
          {
            title: "Value",
            value: alert[:value].to_s,
            short: true
          },
          {
            title: "Severity",
            value: alert[:severity].to_s.capitalize,
            short: true
          },
          {
            title: "Time",
            value: (alert[:fired_at] || alert[:resolved_at]).strftime("%Y-%m-%d %H:%M:%S UTC"),
            short: true
          }
        ],
        footer: "A2A Monitoring",
        ts: (alert[:fired_at] || alert[:resolved_at]).to_i
      }
    end
  end
end
