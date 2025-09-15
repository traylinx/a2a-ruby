# frozen_string_literal: true

module A2A
  class Configuration
    # Module for handling default configuration values
    module Defaults
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
        @rails_integration = defined?(Rails) ? true : false
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
    end
  end
end
