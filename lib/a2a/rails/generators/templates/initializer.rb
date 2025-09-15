# frozen_string_literal: true

# A2A Ruby SDK Configuration
# 
# This file configures the A2A (Agent2Agent) Protocol integration for your Rails application.
# For more information, visit: https://a2a-protocol.org/sdk/ruby/

A2A.configure do |config|
  # Enable Rails integration
  config.rails_integration = true
  
  # Mount path for A2A endpoints (default: "/a2a")
  config.mount_path = "<%= mount_path %>"
  
  # Protocol configuration
  config.protocol_version = "0.3.0"
  config.default_transport = "JSONRPC"
  
  # Feature flags
  config.streaming_enabled = true
  config.push_notifications_enabled = true
  
  # Default MIME types for input/output
  config.default_input_modes = ["text/plain", "application/json"]
  config.default_output_modes = ["text/plain", "application/json"]
  
  # Middleware configuration
  config.middleware_enabled = true
  config.cors_enabled = true
  config.rate_limiting_enabled = false
  config.logging_enabled = Rails.env.development?
  
  # Authentication configuration
  config.authentication_required = <%= with_authentication? %>
  config.webhook_authentication_required = false
  
  # Storage configuration
  <% case storage_backend %>
  <% when "database" %>
  # Database storage (requires running migrations)
  config.task_storage = :database
  <% when "redis" %>
  # Redis storage configuration
  config.task_storage = :redis
  config.redis_config = {
    url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"),
    pool_size: 5,
    pool_timeout: 5
  }
  <% else %>
  # In-memory storage (default - not recommended for production)
  config.task_storage = :memory
  <% end %>
  
  # Timeout configuration
  config.default_timeout = 30
  
  # Logging configuration
  config.log_level = Rails.env.production? ? :info : :debug
  
  # User agent for HTTP requests
  config.user_agent = "#{Rails.application.class.module_parent_name}/#{Rails.application.config.version rescue '1.0.0'} A2A-Ruby/<%= a2a_version %>"
end

# Rails-specific configuration
Rails.application.configure do
  # A2A engine configuration
  config.a2a.enabled = true
  config.a2a.mount_path = "<%= mount_path %>"
  config.a2a.auto_mount = true
  
  # Middleware configuration
  config.a2a.middleware_enabled = true
  config.a2a.cors_enabled = true
  config.a2a.rate_limiting_enabled = false
  config.a2a.logging_enabled = Rails.env.development?
  
  # Authentication configuration
  config.a2a.authentication_required = <%= with_authentication? %>
end

# Environment-specific configuration
case Rails.env
when "development"
  A2A.configure do |config|
    config.log_level = :debug
    config.logging_enabled = true
  end
  
when "test"
  A2A.configure do |config|
    config.task_storage = :memory
    config.log_level = :warn
    config.logging_enabled = false
  end
  
when "production"
  A2A.configure do |config|
    config.log_level = :info
    config.authentication_required = true
    config.webhook_authentication_required = true
    
    # Use Redis in production if available
    if ENV["REDIS_URL"].present?
      config.task_storage = :redis
    end
  end
end