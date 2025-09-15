# frozen_string_literal: true

require "yaml"
require "erb"

##
# Global configuration for the A2A Ruby SDK
#
# Supports environment variables, per-environment configuration,
# configuration inheritance, and validation.
#
# @example Configure the SDK programmatically
#   A2A.configure do |config|
#     config.default_timeout = 30
#     config.log_level = :debug
#     config.protocol_version = "0.3.0"
#   end
#
# @example Load from environment variables
#   # Set A2A_DEFAULT_TIMEOUT=60 in environment
#   config = A2A::Configuration.new
#   config.default_timeout # => 60
#
# @example Load from YAML file
#   A2A.configure_from_file('config/a2a.yml')
#
class A2A::Configuration
  # Default timeout for HTTP requests in seconds
  # @return [Integer]
  attr_accessor :default_timeout

  # Default log level
  # @return [Symbol]
  attr_accessor :log_level

  # A2A protocol version to use
  # @return [String]
  attr_accessor :protocol_version

  # Default transport protocol
  # @return [String]
  attr_accessor :default_transport

  # Enable/disable streaming support
  # @return [Boolean]
  attr_accessor :streaming_enabled

  # Enable/disable push notifications
  # @return [Boolean]
  attr_accessor :push_notifications_enabled

  # Default input MIME types
  # @return [Array<String>]
  attr_accessor :default_input_modes

  # Default output MIME types
  # @return [Array<String>]
  attr_accessor :default_output_modes

  # Redis configuration for task storage and rate limiting
  # @return [Hash]
  attr_accessor :redis_config

  # Enable Rails integration
  # @return [Boolean]
  attr_accessor :rails_integration

  # Rails mount path for A2A endpoints
  # @return [String]
  attr_accessor :mount_path

  # Enable automatic mounting of A2A routes
  # @return [Boolean]
  attr_accessor :auto_mount

  # Enable A2A middleware stack
  # @return [Boolean]
  attr_accessor :middleware_enabled

  # Require authentication for A2A endpoints
  # @return [Boolean]
  attr_accessor :authentication_required

  # Enable CORS middleware
  # @return [Boolean]
  attr_accessor :cors_enabled

  # Enable rate limiting middleware
  # @return [Boolean]
  attr_accessor :rate_limiting_enabled

  # Enable logging middleware
  # @return [Boolean]
  attr_accessor :logging_enabled

  # Require authentication for webhook endpoints
  # @return [Boolean]
  attr_accessor :webhook_authentication_required

  # Custom logger instance
  # @return [Logger, nil]
  attr_accessor :logger

  # User agent string for HTTP requests
  # @return [String]
  attr_accessor :user_agent

  # Environment for configuration (development, test, production)
  # @return [String]
  attr_accessor :environment

  # Configuration file path
  # @return [String, nil]
  attr_accessor :config_file

  # Parent configuration for inheritance
  # @return [Configuration, nil]
  attr_accessor :parent_config

  # Configuration overrides
  # @return [Hash]
  attr_accessor :overrides

  def initialize(environment: nil, parent: nil, **overrides)
    @environment = environment || detect_environment
    @parent_config = parent
    @overrides = overrides
    @config_file = nil

    load_defaults
    load_from_environment
    apply_overrides(overrides)
  end

  private

  # Load default configuration values
  def load_defaults
    @default_timeout = 30
    @log_level = :info
    @protocol_version = "0.3.0"
    @default_transport = "JSONRPC"
    @streaming_enabled = true
    @push_notifications_enabled = true
    @default_input_modes = ["text/plain", "application/json"]
    @default_output_modes = ["text/plain", "application/json"]
    @redis_config = { url: "redis://localhost:6379/0" }
    @rails_integration = defined?(Rails)
    @mount_path = "/a2a"
    @auto_mount = true
    @middleware_enabled = true
    @authentication_required = false
    @cors_enabled = true
    @rate_limiting_enabled = false
    @logging_enabled = true
    @webhook_authentication_required = false
    @logger = nil
    @user_agent = "A2A-Ruby/#{A2A::VERSION}"
  end

  # Load configuration from environment variables
  def load_from_environment
    @default_timeout = env_int("A2A_DEFAULT_TIMEOUT", @default_timeout)
    @log_level = env_symbol("A2A_LOG_LEVEL", @log_level)
    @protocol_version = env_string("A2A_PROTOCOL_VERSION", @protocol_version)
    @default_transport = env_string("A2A_DEFAULT_TRANSPORT", @default_transport)
    @streaming_enabled = env_bool("A2A_STREAMING_ENABLED", @streaming_enabled)
    @push_notifications_enabled = env_bool("A2A_PUSH_NOTIFICATIONS_ENABLED", @push_notifications_enabled)
    @default_input_modes = env_array("A2A_DEFAULT_INPUT_MODES", @default_input_modes)
    @default_output_modes = env_array("A2A_DEFAULT_OUTPUT_MODES", @default_output_modes)
    @rails_integration = env_bool("A2A_RAILS_INTEGRATION", @rails_integration)
    @mount_path = env_string("A2A_MOUNT_PATH", @mount_path)
    @auto_mount = env_bool("A2A_AUTO_MOUNT", @auto_mount)
    @middleware_enabled = env_bool("A2A_MIDDLEWARE_ENABLED", @middleware_enabled)
    @authentication_required = env_bool("A2A_AUTHENTICATION_REQUIRED", @authentication_required)
    @cors_enabled = env_bool("A2A_CORS_ENABLED", @cors_enabled)
    @rate_limiting_enabled = env_bool("A2A_RATE_LIMITING_ENABLED", @rate_limiting_enabled)
    @logging_enabled = env_bool("A2A_LOGGING_ENABLED", @logging_enabled)
    @webhook_authentication_required = env_bool("A2A_WEBHOOK_AUTHENTICATION_REQUIRED",
      @webhook_authentication_required)
    @user_agent = env_string("A2A_USER_AGENT", @user_agent)

    # Redis configuration from environment
    redis_url = ENV["REDIS_URL"] || ENV.fetch("A2A_REDIS_URL", nil)
    return unless redis_url

    @redis_config = { url: redis_url }
  end

  # Apply configuration overrides
  def apply_overrides(overrides)
    overrides.each do |key, value|
      setter = "#{key}="
      raise A2A::Errors::ConfigurationError, "Unknown configuration option: #{key}" unless respond_to?(setter)

      send(setter, value)
    end
  end

  # Detect current environment
  def detect_environment
    return ENV["A2A_ENV"] if ENV["A2A_ENV"]
    return ENV["RAILS_ENV"] if ENV["RAILS_ENV"]
    return ENV["RACK_ENV"] if ENV["RACK_ENV"]
    return Rails.env if defined?(Rails) && Rails.respond_to?(:env)

    "development"
  end

  # Environment variable helpers
  def env_string(key, default)
    ENV[key] || default
  end

  def env_int(key, default)
    value = ENV.fetch(key, nil)
    value ? value.to_i : default
  end

  def env_bool(key, default)
    value = ENV.fetch(key, nil)
    return default if value.nil?

    %w[true yes 1 on].include?(value.downcase)
  end

  def env_symbol(key, default)
    value = ENV.fetch(key, nil)
    value ? value.to_sym : default
  end

  def env_array(key, default)
    value = ENV.fetch(key, nil)
    value ? value.split(",").map(&:strip) : default
  end

  public

  # Get the logger instance
  # @return [Logger]
  def logger
    @logger ||= if defined?(Rails) && Rails.logger
                  Rails.logger
                else
                  require "logger"
                  Logger.new($stdout, level: log_level)
                end
  end

  # Load configuration from YAML file
  # @param file_path [String] Path to YAML configuration file
  # @param environment [String, nil] Environment section to load
  # @return [self]
  def load_from_file(file_path, environment: nil)
    @config_file = file_path
    environment ||= @environment

    raise A2A::Errors::ConfigurationError, "Configuration file not found: #{file_path}" unless File.exist?(file_path)

    begin
      content = File.read(file_path)
      erb_content = ERB.new(content).result
      config_data = YAML.safe_load(erb_content, aliases: true) || {}
    rescue StandardError => e
      raise A2A::Errors::ConfigurationError, "Failed to load configuration file: #{e.message}"
    end

    # Load environment-specific configuration
    env_config = config_data[environment.to_s] || config_data[environment.to_sym] || {}

    # Apply configuration from file
    apply_hash_config(env_config)

    self
  end

  # Merge configuration from another configuration object
  # @param other [Configuration] Configuration to merge from
  # @return [self]
  def merge!(other)
    return self unless other.is_a?(Configuration)

    other.to_h.each do |key, value|
      setter = "#{key}="
      send(setter, value) if respond_to?(setter)
    end

    self
  end

  # Create a child configuration with inheritance
  # @param **overrides [Hash] Configuration overrides
  # @return [Configuration] New configuration instance
  def child(**overrides)
    self.class.new(environment: @environment, parent: self, **overrides)
  end

  # Get configuration value with inheritance support
  # @param key [Symbol, String] Configuration key
  # @return [Object] Configuration value
  def get(key)
    value = send(key) if respond_to?(key)

    # Fall back to parent configuration if value is nil and parent exists
    value = @parent_config.get(key) if value.nil? && @parent_config

    value
  end

  # Convert configuration to hash
  # @return [Hash] Configuration as hash
  def to_h
    {
      environment: @environment,
      default_timeout: @default_timeout,
      log_level: @log_level,
      protocol_version: @protocol_version,
      default_transport: @default_transport,
      streaming_enabled: @streaming_enabled,
      push_notifications_enabled: @push_notifications_enabled,
      default_input_modes: @default_input_modes,
      default_output_modes: @default_output_modes,
      redis_config: @redis_config,
      rails_integration: @rails_integration,
      mount_path: @mount_path,
      auto_mount: @auto_mount,
      middleware_enabled: @middleware_enabled,
      authentication_required: @authentication_required,
      cors_enabled: @cors_enabled,
      rate_limiting_enabled: @rate_limiting_enabled,
      logging_enabled: @logging_enabled,
      webhook_authentication_required: @webhook_authentication_required,
      user_agent: @user_agent
    }
  end

  # Validate the configuration
  # @raise [A2A::Errors::ConfigurationError] if configuration is invalid
  def validate!
    validate_basic_config
    validate_transport_config
    validate_rails_config if rails_integration
    validate_redis_config
    validate_environment_config
  end

  private

  # Apply configuration from hash
  def apply_hash_config(config_hash)
    config_hash.each do |key, value|
      key = key.to_s
      setter = "#{key}="

      if respond_to?(setter)
        send(setter, value)
      else
        # Handle nested configurations
        case key
        when "redis_config", "redis"
          @redis_config = value.is_a?(Hash) ? value.symbolize_keys : { url: value.to_s }
        else
          logger&.warn("Unknown configuration key: #{key}")
        end
      end
    end
  end

  # Validation methods
  def validate_basic_config
    raise A2A::Errors::ConfigurationError, "default_timeout must be positive" if default_timeout <= 0

    if protocol_version.blank?
      raise A2A::Errors::ConfigurationError,
        "protocol_version cannot be blank"
    end

    return if %i[debug info warn error fatal].include?(log_level)

    raise A2A::Errors::ConfigurationError, "log_level must be one of: debug, info, warn, error, fatal"
  end

  def validate_transport_config
    valid_transports = %w[JSONRPC GRPC HTTP+JSON]
    unless valid_transports.include?(default_transport)
      raise A2A::Errors::ConfigurationError, "default_transport must be one of: #{valid_transports.join(", ")}"
    end

    unless default_input_modes.is_a?(Array) && default_input_modes.all?(String)
      raise A2A::Errors::ConfigurationError, "default_input_modes must be an array of strings"
    end

    return if default_output_modes.is_a?(Array) && default_output_modes.all?(String)

    raise A2A::Errors::ConfigurationError, "default_output_modes must be an array of strings"
  end

  def validate_rails_config
    if mount_path && !mount_path.start_with?("/")
      raise A2A::Errors::ConfigurationError, "mount_path must start with '/'"
    end

    return unless defined?(Rails) && Rails.version < "6.0"

    raise A2A::Errors::ConfigurationError,
      "Rails integration requires Rails 6.0 or higher. Current version: #{Rails.version}"
  end

  def validate_redis_config
    raise A2A::Errors::ConfigurationError, "redis_config must be a hash" if redis_config && !redis_config.is_a?(Hash)

    return unless redis_config && redis_config[:url] && !redis_config[:url].is_a?(String)

    raise A2A::Errors::ConfigurationError, "redis_config[:url] must be a string"
  end

  def validate_environment_config
    valid_environments = %w[development test production staging]
    return if valid_environments.include?(environment)

    logger&.warn("Unknown environment: #{environment}. Valid environments: #{valid_environments.join(", ")}")
  end
end
