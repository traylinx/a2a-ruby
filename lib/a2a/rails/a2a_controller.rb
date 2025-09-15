# frozen_string_literal: true

##
# Main controller for A2A Rails engine
#
# This controller handles all A2A protocol endpoints including JSON-RPC requests,
# agent card serving, and streaming responses.
#
class A2A::Rails::A2aController < ApplicationController
  include A2A::Rails::ControllerHelpers

  # Skip CSRF protection for A2A endpoints
  skip_before_action :verify_authenticity_token

  # Handle JSON-RPC requests
  def rpc
    request_body = request.body.read

    begin
      json_rpc_request = A2A::Protocol::JsonRpc.parse_request(request_body)

      # Handle batch requests
      if json_rpc_request.is_a?(Array)
        responses = json_rpc_request.map { |req| handle_single_request(req) }
        render json: responses
      else
        response = handle_single_request(json_rpc_request)
        render json: response
      end
    rescue A2A::Errors::A2AError => e
      render json: build_error_response(e), status: :bad_request
    rescue StandardError => e
      error = A2A::Errors::InternalError.new(e.message)
      render json: build_error_response(error), status: :internal_server_error
    end
  end

  # Serve agent card
  def agent_card
    card = generate_agent_card

    # Support different output formats
    case request.format.symbol
    when :json
      render json: card.to_h
    when :jws
      # TODO: Implement JWS signing
      render json: { error: "JWS format not yet implemented" }, status: :not_implemented
    else
      render json: card.to_h
    end
  rescue StandardError => e
    render json: { error: e.message }, status: :internal_server_error
  end

  # Serve authenticated agent card
  def authenticated_agent_card
    # Ensure authentication is present
    unless authenticated?
      render json: { error: "Authentication required" }, status: :unauthorized
      return
    end

    card = generate_authenticated_agent_card
    render json: card.to_h
  rescue StandardError => e
    render json: { error: e.message }, status: :internal_server_error
  end

  # List capabilities
  def capabilities
    capabilities = collect_capabilities
    render json: { capabilities: capabilities }
  rescue StandardError => e
    render json: { error: e.message }, status: :internal_server_error
  end

  # Health check endpoint
  def health
    render json: {
      status: "healthy",
      version: A2A::VERSION,
      timestamp: Time.current.iso8601,
      rails_version: ::Rails.version
    }
  end

  # Server-Sent Events streaming endpoint
  def stream
    task_id = params[:task_id]

    begin
      task = A2A::Server::TaskManager.instance.get_task(task_id)

      response.headers["Content-Type"] = "text/event-stream"
      response.headers["Cache-Control"] = "no-cache"
      response.headers["Connection"] = "keep-alive"

      # Set up SSE stream
      sse = A2A::Transport::SSE.new(response.stream)

      # Send initial task status
      sse.write_event("task-status", task.to_h)

      # Subscribe to task updates
      subscription = A2A::Server::TaskManager.instance.subscribe_to_task(task_id) do |event|
        case event
        when A2A::Types::TaskStatusUpdateEvent
          sse.write_event("task-status-update", event.to_h)
        when A2A::Types::TaskArtifactUpdateEvent
          sse.write_event("task-artifact-update", event.to_h)
        end
      end

      # Keep connection alive until client disconnects
      loop do
        break if response.stream.closed?

        sleep 1
        sse.write_event("heartbeat", { timestamp: Time.current.iso8601 })
      end
    rescue A2A::Errors::TaskNotFound
      render json: { error: "Task not found" }, status: :not_found
    rescue StandardError => e
      render json: { error: e.message }, status: :internal_server_error
    ensure
      subscription&.unsubscribe
      response.stream.close
    end
  end

  # Webhook endpoint for push notifications
  def webhook
    task_id = params[:task_id]

    begin
      # Verify webhook authentication if configured
      verify_webhook_authentication! if webhook_authentication_required?

      # Process webhook payload
      payload = JSON.parse(request.body.read)

      # Handle different webhook types
      case payload["type"]
      when "task_status_update"
        handle_task_status_webhook(task_id, payload)
      when "task_artifact_update"
        handle_task_artifact_webhook(task_id, payload)
      else
        render json: { error: "Unknown webhook type" }, status: :bad_request
        return
      end

      render json: { status: "processed" }
    rescue JSON::ParserError
      render json: { error: "Invalid JSON payload" }, status: :bad_request
    rescue A2A::Errors::TaskNotFound
      render json: { error: "Task not found" }, status: :not_found
    rescue A2A::Errors::AuthenticationError
      render json: { error: "Webhook authentication failed" }, status: :unauthorized
    rescue StandardError => e
      render json: { error: e.message }, status: :internal_server_error
    end
  end

  private

  def handle_single_request(json_rpc_request)
    # Delegate to the A2A request handler
    handle_a2a_request(json_rpc_request)
  rescue A2A::Errors::A2AError => e
    build_error_response(e, json_rpc_request.id)
  rescue StandardError => e
    error = A2A::Errors::InternalError.new(e.message)
    build_error_response(error, json_rpc_request.id)
  end

  def build_error_response(error, id = nil)
    A2A::Protocol::JsonRpc.build_response(
      error: error.to_json_rpc_error,
      id: id
    )
  end

  def generate_authenticated_agent_card
    # Generate extended agent card with authentication context
    card = generate_agent_card

    # Add authenticated-specific information
    card_hash = card.to_h
    card_hash[:authenticated_user] = current_user_info if respond_to?(:current_user_info)
    card_hash[:permissions] = current_user_permissions if respond_to?(:current_user_permissions)

    A2A::Types::AgentCard.from_h(card_hash)
  end

  def collect_capabilities
    # Collect all registered A2A capabilities from controllers
    capabilities = []

    # Scan all controllers that include A2A::Server::Agent
    ObjectSpace.each_object(Class) do |klass|
      if klass < ActionController::Base && klass.included_modules.include?(A2A::Server::Agent)
        capabilities.concat(klass._a2a_capabilities || [])
      end
    end

    capabilities.map(&:to_h)
  end

  def authenticated?
    # Check if request is authenticated
    # This can be overridden by applications to integrate with their auth system
    request.headers["Authorization"].present? ||
      (respond_to?(:current_user) && current_user.present?)
  end

  def webhook_authentication_required?
    A2A.config.webhook_authentication_required || false
  end

  def verify_webhook_authentication!
    # Verify webhook signature or token
    # This should be implemented based on the specific authentication method
    auth_header = request.headers["Authorization"]

    return if auth_header.present?

    raise A2A::Errors::AuthenticationError, "Missing webhook authentication"

    # TODO: Implement specific webhook authentication logic
    # This could verify HMAC signatures, JWT tokens, etc.
  end

  def handle_task_status_webhook(task_id, payload)
    # Process task status update webhook
    status_data = payload["status"]
    status = A2A::Types::TaskStatus.from_h(status_data)

    A2A::Server::TaskManager.instance.update_task_status(task_id, status)
  end

  def handle_task_artifact_webhook(task_id, payload)
    # Process task artifact update webhook
    artifact_data = payload["artifact"]
    artifact = A2A::Types::Artifact.from_h(artifact_data)
    append = payload["append"] || false

    A2A::Server::TaskManager.instance.update_task_artifact(task_id, artifact, append: append)
  end
end
