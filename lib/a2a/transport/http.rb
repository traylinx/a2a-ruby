# frozen_string_literal: true

require "faraday"
require "faraday/multipart"
require "json"
require "concurrent"

##
# HTTP transport implementation using Faraday adapter pattern
# Provides connection pooling, timeout management, logging, and HTTPS support
#
class A2A::Transport::Http
  # Default configuration values
  DEFAULT_TIMEOUT = 30
  DEFAULT_OPEN_TIMEOUT = 10
  DEFAULT_READ_TIMEOUT = 30
  DEFAULT_WRITE_TIMEOUT = 30
  DEFAULT_POOL_SIZE = 5
  DEFAULT_POOL_TIMEOUT = 5
  DEFAULT_RETRY_COUNT = 3
  DEFAULT_RETRY_DELAY = 1.0

  attr_reader :base_url, :config, :connection

  ##
  # Initialize HTTP transport
  #
  # @param base_url [String] Base URL for the HTTP endpoint
  # @param config [Hash] Configuration options
  # @option config [Integer] :timeout (30) Request timeout in seconds
  # @option config [Integer] :open_timeout (10) Connection open timeout
  # @option config [Integer] :read_timeout (30) Read timeout
  # @option config [Integer] :write_timeout (30) Write timeout
  # @option config [Integer] :pool_size (5) Connection pool size
  # @option config [Integer] :pool_timeout (5) Pool checkout timeout
  # @option config [Integer] :retry_count (3) Number of retries
  # @option config [Float] :retry_delay (1.0) Delay between retries
  # @option config [Boolean] :ssl_verify (true) Verify SSL certificates
  # @option config [String] :ssl_ca_file Path to CA certificate file
  # @option config [String] :ssl_ca_path Path to CA certificate directory
  # @option config [Hash] :headers ({}) Default headers
  # @option config [Boolean] :logging (false) Enable request/response logging
  # @option config [Logger] :logger Logger instance
  # @option config [Hash] :proxy Proxy configuration
  #
  def initialize(base_url, config = {})
    @base_url = base_url
    @config = default_config.merge(config)
    @connection = build_connection
    @metrics = Concurrent::Hash.new(0)
  end

  ##
  # Send HTTP request
  #
  # @param method [Symbol] HTTP method (:get, :post, :put, :delete, etc.)
  # @param path [String] Request path
  # @param params [Hash] Request parameters
  # @param headers [Hash] Request headers
  # @param body [String, Hash] Request body
  # @return [Faraday::Response] HTTP response
  # @raise [A2A::Errors::HTTPError] On HTTP errors
  # @raise [A2A::Errors::TimeoutError] On timeout
  # @raise [A2A::Errors::TransportError] On transport errors
  #
  def request(method, path = "", params: {}, headers: {}, body: nil)
    start_time = Time.zone.now

    begin
      response = @connection.public_send(method, path) do |req|
        req.params.update(params) if params.any?
        req.headers.update(headers) if headers.any?
        req.body = prepare_body(body) if body
      end

      record_metrics(method, response.status, Time.zone.now - start_time)
      handle_response(response)
      response
    rescue A2A::Errors::HTTPError => e
      # Re-raise A2A HTTP errors (from handle_response)
      record_metrics(method, e.status_code || :http_error, Time.zone.now - start_time)
      raise e
    rescue Faraday::TimeoutError => e
      record_metrics(method, :timeout, Time.zone.now - start_time)
      raise A2A::Errors::TimeoutError, "Request timeout: #{e.message}"
    rescue Faraday::ConnectionFailed => e
      record_metrics(method, :connection_failed, Time.zone.now - start_time)
      # Check if it's a timeout-like error
      if e.message.include?("timeout") || e.message.include?("execution expired")
        raise A2A::Errors::TimeoutError, "Request timeout: #{e.message}"
      end

      raise A2A::Errors::TransportError, "Connection failed: #{e.message}"
    rescue Faraday::SSLError => e
      record_metrics(method, :ssl_error, Time.zone.now - start_time)
      raise A2A::Errors::TransportError, "SSL error: #{e.message}"
    rescue Faraday::ClientError => e
      record_metrics(method, :client_error, Time.zone.now - start_time)
      # Handle HTTP status errors from Faraday
      raise A2A::Errors::TransportError, "Client error: #{e.message}" unless e.response && e.response[:status]

      status = e.response[:status]
      case status
      when 400..499
        raise A2A::Errors::HTTPError.new(
          "Client error: #{status}",
          status_code: status,
          response_body: e.response[:body]
        )
      when 500..599
        raise A2A::Errors::HTTPError.new(
          "Server error: #{status}",
          status_code: status,
          response_body: e.response[:body]
        )
      else
        raise A2A::Errors::HTTPError.new(
          "HTTP error: #{status}",
          status_code: status,
          response_body: e.response[:body]
        )
      end
    rescue StandardError => e
      record_metrics(method, :error, Time.zone.now - start_time)
      # Check if it's a timeout-like error
      if e.message.include?("timeout") || e.message.include?("execution expired")
        raise A2A::Errors::TimeoutError, "Request timeout: #{e.message}"
      end

      raise A2A::Errors::TransportError, "Transport error: #{e.message}"
    end
  end

  ##
  # Send GET request
  #
  # @param path [String] Request path
  # @param params [Hash] Query parameters
  # @param headers [Hash] Request headers
  # @return [Faraday::Response] HTTP response
  #
  def get(path = "", params: {}, headers: {})
    request(:get, path, params: params, headers: headers)
  end

  ##
  # Send POST request
  #
  # @param path [String] Request path
  # @param body [String, Hash] Request body
  # @param params [Hash] Query parameters
  # @param headers [Hash] Request headers
  # @return [Faraday::Response] HTTP response
  #
  def post(path = "", body: nil, params: {}, headers: {})
    request(:post, path, params: params, headers: headers, body: body)
  end

  ##
  # Send PUT request
  #
  # @param path [String] Request path
  # @param body [String, Hash] Request body
  # @param params [Hash] Query parameters
  # @param headers [Hash] Request headers
  # @return [Faraday::Response] HTTP response
  #
  def put(path = "", body: nil, params: {}, headers: {})
    request(:put, path, params: params, headers: headers, body: body)
  end

  ##
  # Send DELETE request
  #
  # @param path [String] Request path
  # @param params [Hash] Query parameters
  # @param headers [Hash] Request headers
  # @return [Faraday::Response] HTTP response
  #
  def delete(path = "", params: {}, headers: {})
    request(:delete, path, params: params, headers: headers)
  end

  ##
  # Send JSON-RPC request
  #
  # @param rpc_request [Hash] JSON-RPC request object
  # @param headers [Hash] Additional headers
  # @return [Hash] JSON-RPC response
  # @raise [A2A::Errors::JSONError] On JSON parsing errors
  #
  def json_rpc_request(rpc_request, headers: {})
    default_headers = {
      "Content-Type" => "application/json",
      "Accept" => "application/json"
    }

    response = post(
      body: rpc_request.to_json,
      headers: default_headers.merge(headers)
    )

    parse_json_response(response)
  end

  ##
  # Get connection metrics
  #
  # @return [Hash] Metrics data
  #
  def metrics
    @metrics.to_h
  end

  ##
  # Reset connection metrics
  #
  def reset_metrics!
    @metrics.clear
  end

  ##
  # Close connection and cleanup resources
  #
  def close
    @connection&.close
  end

  private

  ##
  # Build default configuration
  #
  # @return [Hash] Default configuration
  #
  def default_config
    {
      timeout: DEFAULT_TIMEOUT,
      open_timeout: DEFAULT_OPEN_TIMEOUT,
      read_timeout: DEFAULT_READ_TIMEOUT,
      write_timeout: DEFAULT_WRITE_TIMEOUT,
      pool_size: DEFAULT_POOL_SIZE,
      pool_timeout: DEFAULT_POOL_TIMEOUT,
      retry_count: DEFAULT_RETRY_COUNT,
      retry_delay: DEFAULT_RETRY_DELAY,
      ssl_verify: true,
      headers: {},
      logging: false,
      logger: nil,
      proxy: nil
    }
  end

  ##
  # Build Faraday connection with configuration
  #
  # @return [Faraday::Connection] Configured connection
  #
  def build_connection
    Faraday.new(@base_url) do |conn|
      # Request/response middleware
      conn.request :json
      conn.request :multipart
      conn.request :url_encoded

      # NOTE: Retry middleware requires faraday-retry gem
      # Uncomment when faraday-retry is available:
      # conn.request :retry,
      #   max: @config[:retry_count],
      #   interval: @config[:retry_delay],
      #   backoff_factor: 2,
      #   retry_statuses: [429, 500, 502, 503, 504],
      #   methods: [:get, :post, :put, :delete]

      # Logging middleware
      conn.response :logger, @config[:logger] || default_logger if @config[:logging]

      # Response middleware
      conn.response :json, content_type: /\bjson$/
      # NOTE: Not using :raise_error to handle errors manually

      # Adapter (use default net_http adapter)
      # Note: net_http_persistent requires separate gem for connection pooling
      conn.adapter Faraday.default_adapter

      # Configure timeouts
      conn.options.timeout = @config[:timeout]
      conn.options.open_timeout = @config[:open_timeout]
      conn.options.read_timeout = @config[:read_timeout]
      conn.options.write_timeout = @config[:write_timeout]

      # Configure SSL
      conn.ssl.verify = @config[:ssl_verify]
      conn.ssl.ca_file = @config[:ssl_ca_file] if @config[:ssl_ca_file]
      conn.ssl.ca_path = @config[:ssl_ca_path] if @config[:ssl_ca_path]

      # Configure proxy
      conn.proxy = @config[:proxy] if @config[:proxy]

      # Set default headers
      conn.headers.update(@config[:headers]) if @config[:headers].any?
    end
  end

  ##
  # Prepare request body
  #
  # @param body [String, Hash, Object] Request body
  # @return [String] Prepared body
  #
  def prepare_body(body)
    case body
    when String
      body
    when Hash, Array
      body.to_json
    else
      body.respond_to?(:to_json) ? body.to_json : body.to_s
    end
  end

  ##
  # Handle HTTP response
  #
  # @param response [Faraday::Response] HTTP response
  # @return [Faraday::Response] Validated response
  # @raise [A2A::Errors::HTTPError] On HTTP errors
  #
  def handle_response(response)
    case response.status
    when 200..299
      response
    when 400..499
      raise A2A::Errors::HTTPError.new(
        "Client error: #{response.status}",
        status_code: response.status,
        response_body: response.body
      )
    when 500..599
      raise A2A::Errors::HTTPError.new(
        "Server error: #{response.status}",
        status_code: response.status,
        response_body: response.body
      )
    else
      raise A2A::Errors::HTTPError.new(
        "Unexpected status: #{response.status}",
        status_code: response.status,
        response_body: response.body
      )
    end
  end

  ##
  # Parse JSON response
  #
  # @param response [Faraday::Response] HTTP response
  # @return [Hash] Parsed JSON data
  # @raise [A2A::Errors::JSONError] On JSON parsing errors
  #
  def parse_json_response(response)
    return response.body if response.body.is_a?(Hash)

    JSON.parse(response.body)
  rescue JSON::ParserError => e
    raise A2A::Errors::JSONError, "Invalid JSON response: #{e.message}"
  end

  ##
  # Record request metrics
  #
  # @param method [Symbol] HTTP method
  # @param status [Integer, Symbol] Response status or error type
  # @param duration [Float] Request duration in seconds
  #
  def record_metrics(method, status, duration)
    @metrics["#{method}_requests"] += 1
    @metrics["#{method}_#{status}"] += 1
    @metrics["total_requests"] += 1
    @metrics["total_duration"] += duration

    # Track average duration
    @metrics["average_duration"] = @metrics["total_duration"] / @metrics["total_requests"]
  end

  ##
  # Get default logger
  #
  # @return [Logger] Default logger instance
  #
  def default_logger
    logger = Logger.new($stdout)
    logger.level = Logger::INFO
    logger.formatter = proc do |severity, datetime, progname, msg|
      "[#{datetime}] #{severity} -- #{progname}: #{msg}\n"
    end
    logger
  end
end
