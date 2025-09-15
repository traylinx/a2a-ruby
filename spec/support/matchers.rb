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
      
      # Support both string and symbol keys
      jsonrpc = actual["jsonrpc"] || actual[:jsonrpc]
      return false unless jsonrpc == "2.0"
      
      method_name = actual["method"] || actual[:method]
      return false unless method_name.is_a?(String)

      # id can be string, number, or null (for notifications)
      id = actual["id"] || actual[:id]
      return false unless id.nil? || id.is_a?(String) || id.is_a?(Integer)

      # params is optional but must be object or array if present
      params = actual["params"] || actual[:params]
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
      
      # Support both string and symbol keys
      jsonrpc = actual["jsonrpc"] || actual[:jsonrpc]
      return false unless jsonrpc == "2.0"
      
      # Must have id field (can be null)
      has_id = actual.key?("id") || actual.key?(:id)
      return false unless has_id

      # Must have either result or error, but not both
      has_result = actual.key?("result") || actual.key?(:result)
      has_error = actual.key?("error") || actual.key?(:error)
      return false unless has_result ^ has_error

      # If error, validate error structure
      if has_error
        error = actual["error"] || actual[:error]
        return false unless error.is_a?(Hash)
        
        error_code = error["code"] || error[:code]
        return false unless error_code.is_a?(Integer)
        
        error_message = error["message"] || error[:message]
        return false unless error_message.is_a?(String)
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

      # Required fields - support both string and symbol keys
      required_fields = %w[name description version url preferredTransport skills capabilities defaultInputModes
                           defaultOutputModes]
      return false unless required_fields.all? { |field| actual.key?(field) || actual.key?(field.to_sym) }

      # Validate string fields
      string_fields = %w[name description version url preferredTransport]
      string_fields.each do |field|
        value = actual[field] || actual[field.to_sym]
        return false unless value.is_a?(String)
      end

      # Validate skills array
      skills = actual["skills"] || actual[:skills]
      return false unless skills.is_a?(Array)
      return false unless skills.all? { |skill| valid_skill?(skill) }

      # Validate capabilities
      capabilities = actual["capabilities"] || actual[:capabilities]
      return false unless capabilities.is_a?(Hash)

      # Validate defaultInputModes array
      default_input_modes = actual["defaultInputModes"] || actual[:defaultInputModes]
      return false unless default_input_modes.is_a?(Array)

      # Validate defaultOutputModes array
      default_output_modes = actual["defaultOutputModes"] || actual[:defaultOutputModes]
      return false unless default_output_modes.is_a?(Array)

      # Validate transport
      preferred_transport = actual["preferredTransport"] || actual[:preferredTransport]
      return false unless A2A::Types::VALID_TRANSPORTS.include?(preferred_transport)

      # Validate additional interfaces if present
      additional_interfaces = actual["additionalInterfaces"] || actual[:additionalInterfaces]
      if additional_interfaces
        return false unless additional_interfaces.is_a?(Array)
        return false unless additional_interfaces.all? { |interface| valid_interface?(interface) }
      end

      true
    end

    failure_message do |actual|
      "expected #{actual} to be a valid A2A agent card"
    end

    private

    def valid_skill?(skill)
      return false unless skill.is_a?(Hash)

      required_fields = %w[id name description]
      required_fields.all? { |field| skill.key?(field) || skill.key?(field.to_sym) }
    end

    def valid_interface?(interface)
      return false unless interface.is_a?(Hash)

      # Required fields
      transport = interface["transport"] || interface[:transport]
      url = interface["url"] || interface[:url]
      
      return false unless transport.is_a?(String)
      return false unless url.is_a?(String)
      return false unless A2A::Types::VALID_TRANSPORTS.include?(transport)

      true
    end
  end

  # Matcher for validating A2A message structure
  RSpec::Matchers.define :be_valid_a2a_message do
    match do |actual|
      return false unless actual.is_a?(Hash)

      # Required fields - support both string and symbol keys
      required_fields = %w[messageId role kind parts]
      return false unless required_fields.all? { |field| actual.key?(field) || actual.key?(field.to_sym) }

      # Validate role
      role = actual["role"] || actual[:role]
      return false unless A2A::Types::VALID_ROLES.include?(role)

      # Validate kind
      kind = actual["kind"] || actual[:kind]
      return false unless kind == "message"

      # Validate parts
      parts = actual["parts"] || actual[:parts]
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
      
      # Support both string and symbol keys
      kind = part["kind"] || part[:kind]
      return false unless kind
      return false unless A2A::Types::VALID_PART_KINDS.include?(kind)

      case kind
      when "text"
        part.key?("text") || part.key?(:text)
      when "file"
        part.key?("file") || part.key?(:file)
      when "data"
        part.key?("data") || part.key?(:data)
      else
        false
      end
    end
  end

  # Matcher for validating A2A task structure
  RSpec::Matchers.define :be_valid_a2a_task do
    match do |actual|
      return false unless actual.is_a?(Hash)

      # Required fields - support both string and symbol keys
      required_fields = %w[id contextId kind status]
      return false unless required_fields.all? { |field| actual.key?(field) || actual.key?(field.to_sym) }

      # Validate kind
      kind = actual["kind"] || actual[:kind]
      return false unless kind == "task"

      # Validate status
      status = actual["status"] || actual[:status]
      return false unless status.is_a?(Hash)
      
      state = status["state"] || status[:state]
      return false unless state
      return false unless A2A::Types::VALID_TASK_STATES.include?(state)

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

      # Required fields - support both string and symbol keys
      required_fields = %w[taskId contextId status]
      return false unless required_fields.all? { |field| actual.key?(field) || actual.key?(field.to_sym) }

      # Validate status
      status = actual["status"] || actual[:status]
      return false unless status.is_a?(Hash)
      
      state = status["state"] || status[:state]
      return false unless state
      return false unless A2A::Types::VALID_TASK_STATES.include?(state)

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

      # Required fields - support both string and symbol keys
      required_fields = %w[taskId contextId artifact]
      return false unless required_fields.all? { |field| actual.key?(field) || actual.key?(field.to_sym) }

      # Validate artifact
      artifact = actual["artifact"] || actual[:artifact]
      return false unless artifact.is_a?(Hash)
      
      artifact_id = artifact["artifactId"] || artifact[:artifactId]
      return false unless artifact_id
      
      parts = artifact["parts"] || artifact[:parts]
      return false unless parts
      return false unless parts.is_a?(Array)

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
      
      # Support both string and symbol keys
      has_error = actual.key?("error") || actual.key?(:error)
      return false unless has_error

      error = actual["error"] || actual[:error]
      return false unless error.is_a?(Hash)
      
      error_code = error["code"] || error[:code]
      return false unless error_code == expected_code

      true
    end

    failure_message do |actual|
      error_code = (actual["error"] || actual[:error])&.dig("code") || 
                   (actual["error"] || actual[:error])&.dig(:code)
      "expected JSON-RPC error with code #{expected_code}, got #{error_code}"
    end
  end

  # Matcher for validating A2A-specific error codes
  RSpec::Matchers.define :have_a2a_error do |expected_code|
    match do |actual|
      return false unless actual.is_a?(Hash)
      
      # Support both string and symbol keys
      has_error = actual.key?("error") || actual.key?(:error)
      return false unless has_error

      error = actual["error"] || actual[:error]
      return false unless error.is_a?(Hash)
      
      error_code = error["code"] || error[:code]
      return false unless error_code == expected_code

      # Verify it's an A2A error code (in the -32001 to -32010 range)
      return false unless (-32_010..-32_001).cover?(expected_code)

      true
    end

    failure_message do |actual|
      error_code = (actual["error"] || actual[:error])&.dig("code") || 
                   (actual["error"] || actual[:error])&.dig(:code)
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

      # Required fields - support both string and symbol keys
      url = actual["url"] || actual[:url]
      return false unless url
      return false unless url.is_a?(String)

      # Optional fields validation
      id = actual["id"] || actual[:id]
      return false if id && !id.is_a?(String)

      auth = actual["authentication"] || actual[:authentication]
      if auth
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
