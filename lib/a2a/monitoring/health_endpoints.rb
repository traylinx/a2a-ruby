# frozen_string_literal: true

module A2A::Monitoring
  ##
  # Health check endpoints for A2A applications
  #
  # Provides standard health check endpoints that can be used
  # by load balancers, monitoring systems, and orchestrators.
  #
  class HealthEndpoints
    # Initialize health endpoints
    # @param health_checker [A2A::Monitoring::HealthChecker] Health checker instance
    def initialize(health_checker = A2A::Monitoring.health_checks)
      @health_checker = health_checker
      setup_default_checks
    end

    # Handle health check request
    # @param request [Hash] HTTP request data
    # @return [Array] Rack response array
    def call(env)
      path = env["PATH_INFO"]

      case path
      when "/health"
        handle_health_check
      when "/health/ready"
        handle_readiness_check
      when "/health/live"
        handle_liveness_check
      when "/metrics"
        handle_metrics_endpoint
      else
        [404, { "Content-Type" => "application/json" }, ['{"error":"Not Found"}']]
      end
    end

    private

    # Handle general health check
    def handle_health_check
      health_result = @health_checker.check_health
      status_code = health_result[:status] == :healthy ? 200 : 503

      [status_code, json_headers, [health_result.to_json]]
    end

    # Handle readiness check (can serve traffic)
    def handle_readiness_check
      # Check if application is ready to serve requests
      ready = check_readiness
      status_code = ready ? 200 : 503

      response = {
        status: ready ? "ready" : "not_ready",
        timestamp: Time.now.iso8601
      }

      [status_code, json_headers, [response.to_json]]
    end

    # Handle liveness check (application is running)
    def handle_liveness_check
      # Simple liveness check - if we can respond, we're alive
      response = {
        status: "alive",
        timestamp: Time.now.iso8601,
        uptime: Process.clock_gettime(Process::CLOCK_MONOTONIC)
      }

      [200, json_headers, [response.to_json]]
    end

    # Handle metrics endpoint
    def handle_metrics_endpoint
      if defined?(Prometheus)
        # Return Prometheus metrics format
        metrics = Prometheus::Client.registry.metrics
        prometheus_output = Prometheus::Client::Formats::Text.marshal(metrics)
        [200, { "Content-Type" => "text/plain" }, [prometheus_output]]
      else
        # Return JSON metrics
        metrics = A2A::Monitoring.metrics.current_metrics
        [200, json_headers, [{ metrics: metrics }.to_json]]
      end
    end

    def json_headers
      { "Content-Type" => "application/json" }
    end

    def check_readiness
      # Check database connectivity if using database storage
      return false unless check_database_connection

      # Check Redis connectivity if using Redis
      return false unless check_redis_connection

      # Check plugin system
      return false unless check_plugins_loaded

      true
    end

    def check_database_connection
      return true unless A2A.config.rails_integration

      if defined?(ActiveRecord)
        ActiveRecord::Base.connection.active?
      else
        true
      end
    rescue StandardError
      false
    end

    def check_redis_connection
      redis_config = A2A.config.redis_config
      return true unless redis_config && redis_config[:url]

      if defined?(Redis)
        redis = Redis.new(url: redis_config[:url])
        redis.ping == "PONG"
      else
        true
      end
    rescue StandardError
      false
    end

    def check_plugins_loaded
      # Check if critical plugins are loaded
      critical_plugins = A2A.config.get(:critical_plugins) || []

      critical_plugins.all? do |plugin_name|
        A2A::Plugin.loaded?(plugin_name)
      end
    end

    def setup_default_checks
      # Register default health checks
      @health_checker.register_check(:configuration) do
        A2A.config.validate!
        { status: :healthy, message: "Configuration is valid" }
      rescue StandardError => e
        { status: :unhealthy, message: "Configuration error: #{e.message}" }
      end

      @health_checker.register_check(:memory_usage) do
        # Check memory usage (basic check)
        if defined?(GC)
          stat = GC.stat
          heap_used = stat[:heap_allocated_pages] * stat[:heap_page_size]

          # Simple threshold check (adjust as needed)
          if heap_used > 500_000_000 # 500MB
            { status: :warning, message: "High memory usage: #{heap_used} bytes" }
          else
            { status: :healthy, message: "Memory usage: #{heap_used} bytes" }
          end
        else
          { status: :healthy, message: "Memory check not available" }
        end
      end

      @health_checker.register_check(:plugin_system) do
        loaded_count = A2A::Plugin.loaded_plugins.size
        registered_count = A2A::Plugin.registry.size

        {
          status: :healthy,
          message: "Plugins: #{loaded_count}/#{registered_count} loaded"
        }
      end
    end
  end

  ##
  # Rack middleware for health endpoints
  #
  class HealthMiddleware
    def initialize(app, health_endpoints = nil)
      @app = app
      @health_endpoints = health_endpoints || HealthEndpoints.new
    end

    def call(env)
      # Check if this is a health endpoint request
      if health_endpoint?(env["PATH_INFO"])
        @health_endpoints.call(env)
      else
        @app.call(env)
      end
    end

    private

    def health_endpoint?(path)
      path&.start_with?("/health") || path == "/metrics"
    end
  end
end
