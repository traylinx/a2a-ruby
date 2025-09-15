# frozen_string_literal: true

##
# Example custom middleware plugin
#
# Demonstrates how to create a custom middleware plugin
# for the A2A plugin architecture.
#
class A2A::Plugins::ExampleMiddleware < A2A::Plugin::MiddlewarePlugin
  # Middleware name for identification
  def middleware_name
    "example"
  end

  # Process request through middleware
  # @param request [Hash] Request data
  # @param next_middleware [Proc] Next middleware in chain
  # @return [Object] Response
  def call(request, next_middleware)
    start_time = Time.now

    logger&.info("Example Middleware: Processing request #{request[:id]}")

    # Pre-processing
    request = preprocess_request(request)

    begin
      # Call next middleware in chain
      response = next_middleware.call(request)

      # Post-processing
      response = postprocess_response(response, request)

      # Log success
      duration = Time.now - start_time
      logger&.info("Example Middleware: Request completed in #{duration.round(3)}s")

      response
    rescue StandardError => e
      # Error handling
      duration = Time.now - start_time
      logger&.error("Example Middleware: Request failed after #{duration.round(3)}s: #{e.message}")

      # Execute error hooks
      A2A::Plugin.execute_hooks(A2A::Plugin::Events::REQUEST_ERROR, e, request)

      raise
    end
  end

  # Register hooks for this plugin
  def register_hooks(plugin_manager)
    plugin_manager.add_hook(A2A::Plugin::Events::BEFORE_REQUEST, priority: 10) do |request|
      logger&.debug("Example Middleware: Adding request metadata")
      request[:middleware_metadata] ||= {}
      request[:middleware_metadata][:example] = {
        processed_at: Time.now.iso8601,
        version: "1.0.0"
      }
    end
  end

  private

  def setup
    @request_counter = 0
    @error_counter = 0
    logger&.info("Example Middleware plugin initialized")
  end

  def cleanup
    logger&.info("Example Middleware plugin cleaned up (processed #{@request_counter} requests, #{@error_counter} errors)")
  end

  def preprocess_request(request)
    @request_counter += 1

    # Add request ID if not present
    request[:id] ||= SecureRandom.uuid

    # Add processing metadata
    request[:processing] ||= {}
    request[:processing][:middleware_start] = Time.now.to_f

    # Validate request structure
    validate_request_structure(request)

    request
  end

  def postprocess_response(response, request)
    # Add processing time to response metadata
    if request[:processing] && request[:processing][:middleware_start]
      processing_time = Time.now.to_f - request[:processing][:middleware_start]

      if response.is_a?(Hash)
        response[:metadata] ||= {}
        response[:metadata][:processing_time] = processing_time
      end
    end

    response
  end

  def validate_request_structure(request)
    raise A2A::Errors::InvalidRequest, "Request must be a hash" unless request.is_a?(Hash)

    return if request[:method]

    raise A2A::Errors::InvalidRequest, "Request must have a method"

    # Additional validation can be added here
  end
end
