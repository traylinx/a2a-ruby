# frozen_string_literal: true

module A2A
  class Configuration
    # Module for loading configuration from environment variables
    module EnvironmentLoader
      private

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

      # Detect current environment
      def detect_environment
        return ENV["A2A_ENV"] if ENV["A2A_ENV"]
        return ENV["RAILS_ENV"] if ENV["RAILS_ENV"]
        return ENV["RACK_ENV"] if ENV["RACK_ENV"]
        return rails_environment if rails_environment

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
    end
  end
end
