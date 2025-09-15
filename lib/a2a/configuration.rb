# frozen_string_literal: true

require_relative "utils/rails_detection"
require_relative "configuration/defaults"
require_relative "configuration/environment_loader"
require_relative "configuration/file_loader"
require_relative "configuration/validator"
require_relative "configuration/inheritance"

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
module A2A
  class Configuration
    include A2A::Utils::RailsDetection
    include Defaults
    include EnvironmentLoader
    include FileLoader
    include Validator
    include Inheritance

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

    # Apply configuration overrides
    def apply_overrides(overrides)
      overrides.each do |key, value|
        setter = "#{key}="
        unless respond_to?(setter, true) # Check for both public and private methods
          raise A2A::Errors::ConfigurationError, "Unknown configuration option: #{key}"
        end

        send(setter, value)
      end
    end

    public

    # Get the logger instance
    # @return [Logger]
    def logger
      @logger ||= if rails_available? && rails_logger
                    rails_logger
                  else
                    require "logger"
                    Logger.new($stdout, level: log_level)
                  end
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
  end
end
