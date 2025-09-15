# frozen_string_literal: true

##
# Example custom authentication plugin
#
# Demonstrates how to create a custom authentication plugin
# for the A2A plugin architecture.
#
class A2A::Plugins::ExampleAuth < A2A::Plugin::AuthPlugin
  # Authentication strategy name
  def strategy_name
    "example"
  end

  # Authenticate request
  # @param request [Hash] Request data
  # @param **options [Hash] Authentication options
  # @return [Hash] Authenticated request
  def authenticate_request(request, **options)
    logger&.info("Authenticating request with Example Auth")

    # Add custom authentication header
    request[:headers] ||= {}
    request[:headers]["X-Example-Auth"] = generate_token(options)

    request
  end

  # Validate credentials
  # @param credentials [Hash] Credentials to validate
  # @return [Boolean] Whether credentials are valid
  def validate_credentials(credentials)
    return false unless credentials.is_a?(Hash)
    return false unless credentials[:api_key]

    # Simple validation - in real implementation, validate against backend
    credentials[:api_key].start_with?("example_")
  end

  # Register hooks for this plugin
  def register_hooks(plugin_manager)
    plugin_manager.add_hook(A2A::Plugin::Events::BEFORE_REQUEST) do |request|
      logger&.debug("Example Auth: Validating request authentication")

      # Add request timestamp for security
      request[:auth_timestamp] = Time.now.to_i
    end

    plugin_manager.add_hook(A2A::Plugin::Events::REQUEST_ERROR) do |error, request|
      if error.is_a?(A2A::Errors::AuthenticationError)
        logger&.warn("Example Auth: Authentication failed for request #{request[:id]}")
      end
    end
  end

  private

  def setup
    @secret_key = config[:secret_key] || "default_secret"
    logger&.info("Example Auth plugin initialized")
  end

  def cleanup
    @secret_key = nil
    logger&.info("Example Auth plugin cleaned up")
  end

  def generate_token(options)
    # Simple token generation - in real implementation, use proper JWT or similar
    payload = {
      timestamp: Time.now.to_i,
      client_id: options[:client_id] || "unknown"
    }

    Base64.encode64("#{payload.to_json}:#{@secret_key}").strip
  end
end
