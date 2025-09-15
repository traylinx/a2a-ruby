# frozen_string_literal: true

##
# Custom RSpec matchers for A2A protocol testing
# These matchers provide domain-specific assertions for A2A types and protocol compliance
#
module A2AMatchers
  # Matcher for validating JSON-RPC 2.0 request format
  RSpec::Matchers.define :be_valid_json_rpc_request do
    match do |actual|
      return false unless actual.is_a?(Hash)
      return false unless actual["jsonrpc"] == "2.0"
      return false unless actual["method"].is_a?(String)

      # id can be string, number, or null (for notifications)
      id = actual["id"]
      return false unless id.nil? || id.is_a?(String) || id.is_a?(Integer)

      # params is optional but must be object or array if present
      params = actual["params"]
      return false if params && !params.is_a?(Hash) && !params.is_a?(Array)

      true
    end

    failure_message do |actual|
      "expected #{actual} to be a valid JSON-RPC 2.0 request"
    end

    failure_message_when_negated do |actual|
      "expected #{actual} not to be a valid JSON-RPC 2.0 request"
    end
  end

  # Matcher for validating JSON-RPC 2.0 response format
  RSpec::Matchers.define :be_valid_json_rpc_response do
    match do |actual|
      return false unless actual.is_a?(Hash)
      return false unless actual["jsonrpc"] == "2.0"
      return false unless actual.key?("id")

      # Must have either result or error, but not both
      has_result = actual.key?("result")
      has_error = actual.key?("error")
      return false unless has_result ^ has_error

      # If error, validate error structure
      if has_error
        error = actual["error"]
        return false unless error.is_a?(Hash)
        return false unless error["code"].is_a?(Integer)
        return false unless error["message"].is_a?(String)
      end

      true
    end

    failure_message do |actual|
      "expected #{actual} to be a valid JSON-RPC 2.0 response"
    end
  end

  # Matcher for validating A2A agent card structure
  RSpec::Matchers.define :be_valid_agent_card do
    match do |actual|
      return false unless actual.is_a?(Hash)

      # Required fields
      required_fields = %w[name description version url preferredTransport skills capabilities defaultInputModes
                           defaultOutputModes]
      return false unless required_fields.all? { |field| actual.key?(field) }

      # Validate skills array
      skills = actual["skills"]
      return false unless skills.is_a?(Array)
      return false unless skills.all? { |skill| valid_skill?(skill) }

      # Validate capabilities
      capabilities = actual["capabilities"]
      return false unless capabilities.is_a?(Hash)

      # Validate transport
      return false unless A2A::Types::VALID_TRANSPORTS.include?(actual["preferredTransport"])

      true
    end

    failure_message do |actual|
      "expected #{actual} to be a valid A2A agent card"
    end

    private

    def valid_skill?(skill)
      return false unless skill.is_a?(Hash)

      required_fields = %w[id name description]
      required_fields.all? { |field| skill.key?(field) }
    end
  end

  # Matcher for validating A2A message structure
  RSpec::Matchers.define :be_valid_a2a_message do
    match do |actual|
      return false unless actual.is_a?(Hash)

      # Required fields
      required_fields = %w[messageId role kind parts]
      return false unless required_fields.all? { |field| actual.key?(field) }

      # Validate role
      return false unless A2A::Types::VALID_ROLES.include?(actual["role"])

      # Validate kind
      return false unless actual["kind"] == "message"

      # Validate parts
      parts = actual["parts"]
      return false unless parts.is_a?(Array)
      return false if parts.empty?
      return false unless parts.all? { |part| valid_part?(part) }

      true
    end

    failure_message do |actual|
      "expected #{actual} to be a valid A2A message"
    end

    def valid_part?(part)
      return false unless part.is_a?(Hash)
      return false unless part.key?("kind")
      return false unless A2A::Types::VALID_PART_KINDS.include?(part["kind"])

      case part["kind"]
      when "text"
        part.key?("text")
      when "file"
        part.key?("file")
      when "data"
        part.key?("data")
      else
        false
      end
    end
  end

  # Matcher for validating A2A task structure
  RSpec::Matchers.define :be_valid_a2a_task do
    match do |actual|
      return false unless actual.is_a?(Hash)

      # Required fields
      required_fields = %w[id contextId kind status]
      return false unless required_fields.all? { |field| actual.key?(field) }

      # Validate kind
      return false unless actual["kind"] == "task"

      # Validate status
      status = actual["status"]
      return false unless status.is_a?(Hash)
      return false unless status.key?("state")
      return false unless A2A::Types::VALID_TASK_STATES.include?(status["state"])

      true
    end

    failure_message do |actual|
      "expected #{actual} to be a valid A2A task"
    end
  end

  # Matcher for validating task status update events
  RSpec::Matchers.define :be_valid_task_status_update_event do
    match do |actual|
      return false unless actual.is_a?(Hash)

      # Required fields
      required_fields = %w[taskId contextId status]
      return false unless required_fields.all? { |field| actual.key?(field) }

      # Validate status
      status = actual["status"]
      return false unless status.is_a?(Hash)
      return false unless status.key?("state")
      return false unless A2A::Types::VALID_TASK_STATES.include?(status["state"])

      true
    end

    failure_message do |actual|
      "expected #{actual} to be a valid task status update event"
    end
  end

  # Matcher for validating task artifact update events
  RSpec::Matchers.define :be_valid_task_artifact_update_event do
    match do |actual|
      return false unless actual.is_a?(Hash)

      # Required fields
      required_fields = %w[taskId contextId artifact]
      return false unless required_fields.all? { |field| actual.key?(field) }

      # Validate artifact
      artifact = actual["artifact"]
      return false unless artifact.is_a?(Hash)
      return false unless artifact.key?("artifactId")
      return false unless artifact.key?("parts")
      return false unless artifact["parts"].is_a?(Array)

      true
    end

    failure_message do |actual|
      "expected #{actual} to be a valid task artifact update event"
    end
  end

  # Matcher for validating JSON-RPC error codes
  RSpec::Matchers.define :have_json_rpc_error do |expected_code|
    match do |actual|
      return false unless actual.is_a?(Hash)
      return false unless actual.key?("error")

      error = actual["error"]
      return false unless error.is_a?(Hash)
      return false unless error["code"] == expected_code

      true
    end

    failure_message do |actual|
      error_code = actual.dig("error", "code")
      "expected JSON-RPC error with code #{expected_code}, got #{error_code}"
    end
  end

  # Matcher for validating A2A-specific error codes
  RSpec::Matchers.define :have_a2a_error do |expected_code|
    match do |actual|
      return false unless actual.is_a?(Hash)
      return false unless actual.key?("error")

      error = actual["error"]
      return false unless error.is_a?(Hash)
      return false unless error["code"] == expected_code

      # Verify it's an A2A error code (in the -32001 to -32010 range)
      return false unless (-32_010..-32_001).cover?(expected_code)

      true
    end

    failure_message do |actual|
      error_code = actual.dig("error", "code")
      "expected A2A error with code #{expected_code}, got #{error_code}"
    end
  end

  # Matcher for validating streaming responses
  RSpec::Matchers.define :be_streaming_response do
    match do |actual|
      # Should be an Enumerator for streaming responses
      actual.is_a?(Enumerator)
    end

    failure_message do |actual|
      "expected #{actual} to be a streaming response (Enumerator)"
    end
  end

  # Matcher for validating Server-Sent Events format
  RSpec::Matchers.define :be_valid_sse_event do
    match do |actual|
      return false unless actual.is_a?(String)

      # SSE events should have data: prefix
      lines = actual.strip.split("\n")
      return false if lines.empty?

      # At least one line should start with "data:"
      lines.any? { |line| line.start_with?("data:") }
    end

    failure_message do |actual|
      "expected #{actual} to be a valid Server-Sent Event"
    end
  end

  # Matcher for validating push notification configs
  RSpec::Matchers.define :be_valid_push_notification_config do
    match do |actual|
      return false unless actual.is_a?(Hash)

      # Required fields
      return false unless actual.key?("url")
      return false unless actual["url"].is_a?(String)

      # Optional fields validation
      return false if actual.key?("id") && !actual["id"].is_a?(String)

      if actual.key?("authentication")
        auth = actual["authentication"]
        return false unless auth.is_a?(Hash)
      end

      true
    end

    failure_message do |actual|
      "expected #{actual} to be a valid push notification config"
    end
  end

  # Matcher for validating transport protocols
  RSpec::Matchers.define :be_valid_transport do
    match do |actual|
      A2A::Types::VALID_TRANSPORTS.include?(actual)
    end

    failure_message do |actual|
      "expected #{actual} to be a valid transport protocol (#{A2A::Types::VALID_TRANSPORTS.join(', ')})"
    end
  end

  # Matcher for validating task states
  RSpec::Matchers.define :be_valid_task_state do
    match do |actual|
      A2A::Types::VALID_TASK_STATES.include?(actual)
    end

    failure_message do |actual|
      "expected #{actual} to be a valid task state (#{A2A::Types::VALID_TASK_STATES.join(', ')})"
    end
  end

  # Matcher for validating message roles
  RSpec::Matchers.define :be_valid_message_role do
    match do |actual|
      A2A::Types::VALID_ROLES.include?(actual)
    end

    failure_message do |actual|
      "expected #{actual} to be a valid message role (#{A2A::Types::VALID_ROLES.join(', ')})"
    end
  end
end

RSpec.configure do |config|
  config.include A2AMatchers
end
