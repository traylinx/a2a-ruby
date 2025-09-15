# frozen_string_literal: true

module A2A
  class Configuration
    # Module for configuration validation
    module Validator
      # Validate the configuration
      # @raise [A2A::Errors::ConfigurationError] if configuration is invalid
      def validate!
        errors = []

        begin
          validate_basic_config
        rescue A2A::Errors::ConfigurationError => e
          errors << e.message
        end

        begin
          validate_transport_config
        rescue A2A::Errors::ConfigurationError => e
          errors << e.message
        end

        if rails_integration
          begin
            validate_rails_config
          rescue A2A::Errors::ConfigurationError => e
            errors << e.message
          end
        end

        begin
          validate_redis_config
        rescue A2A::Errors::ConfigurationError => e
          errors << e.message
        end

        begin
          validate_environment_config
        rescue A2A::Errors::ConfigurationError => e
          errors << e.message
        end

        begin
          validate_timeout_values
        rescue A2A::Errors::ConfigurationError => e
          errors << e.message
        end

        begin
          validate_boolean_options
        rescue A2A::Errors::ConfigurationError => e
          errors << e.message
        end

        unless errors.empty?
          raise A2A::Errors::ConfigurationError,
                "Configuration validation failed:\n  - #{errors.join("\n  - ")}"
        end

        true
      end

      private

      # Validation methods
      def validate_basic_config
        raise A2A::Errors::ConfigurationError, "default_timeout must be positive" if default_timeout <= 0

        validate_log_level
        validate_protocol_version
      end

      # Validate log level with proper string/symbol handling
      def validate_log_level
        return if log_level.nil?

        # Accept both string and symbol log levels, normalize to symbol
        normalized_level = log_level.to_s.downcase
        valid_levels = %w[debug info warn error fatal]

        unless valid_levels.include?(normalized_level)
          raise A2A::Errors::ConfigurationError,
                "log_level must be one of: #{valid_levels.join(', ')}. Got: #{log_level.inspect}"
        end

        # Normalize to symbol for internal use
        @log_level = normalized_level.to_sym
      end

      # Validate protocol version with proper nil/blank handling
      def validate_protocol_version
        return if protocol_version.nil?

        if protocol_version.respond_to?(:strip) && protocol_version.strip.empty?
          raise A2A::Errors::ConfigurationError,
                "protocol_version cannot be blank"
        elsif protocol_version.respond_to?(:empty?) && protocol_version.empty?
          raise A2A::Errors::ConfigurationError,
                "protocol_version cannot be empty"
        end
      end

      def validate_transport_config
        valid_transports = %w[JSONRPC GRPC HTTP+JSON]
        unless valid_transports.include?(default_transport)
          raise A2A::Errors::ConfigurationError, "default_transport must be one of: #{valid_transports.join(', ')}"
        end

        unless default_input_modes.is_a?(Array) && default_input_modes.all?(String)
          raise A2A::Errors::ConfigurationError, "default_input_modes must be an array of strings"
        end

        return if default_output_modes.is_a?(Array) && default_output_modes.all?(String)

        raise A2A::Errors::ConfigurationError, "default_output_modes must be an array of strings"
      end

      def validate_rails_config
        raise A2A::Errors::ConfigurationError, "mount_path must start with '/'" if mount_path && !mount_path.start_with?("/")

        # Only validate Rails version if Rails is available and version checking is needed
        return unless rails_available? && rails_version_requires_validation?

        current_version = rails_version
        raise A2A::Errors::ConfigurationError,
              "Rails integration requires Rails 6.0 or higher. Current version: #{current_version}"
      end

      def validate_redis_config
        raise A2A::Errors::ConfigurationError, "redis_config must be a hash" if redis_config && !redis_config.is_a?(Hash)

        return unless redis_config && redis_config[:url] && !redis_config[:url].is_a?(String)

        raise A2A::Errors::ConfigurationError, "redis_config[:url] must be a string"
      end

      def validate_environment_config
        return if environment.nil?

        raise A2A::Errors::ConfigurationError, "environment must be a string" unless environment.is_a?(String)

        valid_environments = %w[development test production staging]
        return if valid_environments.include?(environment)

        logger&.warn("Unknown environment: #{environment}. Valid environments: #{valid_environments.join(', ')}")
      end

      def validate_timeout_values
        return unless default_timeout && (!default_timeout.is_a?(Numeric) || default_timeout <= 0)

        raise A2A::Errors::ConfigurationError,
              "default_timeout must be a positive number, got: #{default_timeout.inspect}"
      end

      def validate_boolean_options
        boolean_options = {
          streaming_enabled: streaming_enabled,
          push_notifications_enabled: push_notifications_enabled,
          rails_integration: rails_integration,
          auto_mount: auto_mount,
          middleware_enabled: middleware_enabled,
          authentication_required: authentication_required,
          cors_enabled: cors_enabled,
          rate_limiting_enabled: rate_limiting_enabled,
          logging_enabled: logging_enabled,
          webhook_authentication_required: webhook_authentication_required
        }

        boolean_options.each do |option, value|
          next if value.nil?
          next if [true, false].include?(value)

          raise A2A::Errors::ConfigurationError,
                "#{option} must be true or false, got: #{value.inspect}"
        end
      end
    end
  end
end
