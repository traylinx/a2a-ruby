# frozen_string_literal: true

require "factory_bot"

##
# FactoryBot configuration for A2A testing
# Following patterns from a2a-python factories
#
FactoryBot.define do
  # A2A Message factory
  factory :a2a_message, class: Hash do
    message_id { SecureRandom.uuid }
    role { "user" }
    kind { "message" }
    parts { [{ kind: "text", text: "Hello, agent!" }] }

    trait :agent_message do
      role { "agent" }
    end

    trait :with_context do
      context_id { SecureRandom.uuid }
      task_id { SecureRandom.uuid }
    end

    trait :with_file do
      parts do
        [
          { kind: "text", text: "Here's a file:" },
          {
            kind: "file",
            file: {
              name: "test.txt",
              mimeType: "text/plain",
              bytes: Base64.encode64("Test file content")
            }
          }
        ]
      end
    end

    initialize_with { attributes }
  end

  # A2A Task factory
  factory :a2a_task, class: Hash do
    id { SecureRandom.uuid }
    context_id { SecureRandom.uuid }
    kind { "task" }
    status { { state: "submitted", updatedAt: Time.current.iso8601 } }

    trait :working do
      status { { state: "working", updatedAt: Time.current.iso8601 } }
    end

    trait :completed do
      status { { state: "completed", updatedAt: Time.current.iso8601 } }
    end

    trait :with_history do
      history { [build(:a2a_message)] }
    end

    trait :with_artifacts do
      artifacts do
        [
          {
            artifactId: SecureRandom.uuid,
            name: "Test Artifact",
            parts: [{ kind: "text", text: "Artifact content" }]
          }
        ]
      end
    end

    initialize_with { attributes }
  end

  # A2A Agent Card factory
  factory :a2a_agent_card, class: Hash do
    name { "Test Agent" }
    description { "A test agent for A2A protocol testing" }
    version { "1.0.0" }
    url { "https://test-agent.example.com/a2a" }
    preferred_transport { "JSONRPC" }
    protocol_version { "0.3.0" }

    skills do
      [
        {
          id: "test_skill",
          name: "Test Skill",
          description: "A test skill for demonstration",
          tags: %w[test example],
          examples: ["Hello", "How are you?"]
        }
      ]
    end

    capabilities do
      {
        streaming: true,
        pushNotifications: true,
        stateTransitionHistory: true
      }
    end

    default_input_modes { ["text/plain", "application/json"] }
    default_output_modes { ["text/plain", "application/json"] }

    trait :with_multiple_transports do
      additional_interfaces do
        [
          { transport: "GRPC", url: "https://grpc.test-agent.example.com" },
          { transport: "HTTP+JSON", url: "https://rest.test-agent.example.com" }
        ]
      end
    end

    trait :with_security do
      security { [{ "oauth2" => %w[read write] }] }
      security_schemes do
        {
          "oauth2" => {
            type: "oauth2",
            flows: {
              clientCredentials: {
                tokenUrl: "https://auth.example.com/token",
                scopes: {
                  "read" => "Read access",
                  "write" => "Write access"
                }
              }
            }
          }
        }
      end
    end

    initialize_with { attributes }
  end

  # Task Status Update Event factory
  factory :task_status_update_event, class: Hash do
    task_id { SecureRandom.uuid }
    context_id { SecureRandom.uuid }
    status { { state: "working", updatedAt: Time.current.iso8601 } }

    trait :completed do
      status { { state: "completed", updatedAt: Time.current.iso8601 } }
    end

    trait :failed do
      status do
        {
          state: "failed",
          error: "Task execution failed",
          updatedAt: Time.current.iso8601
        }
      end
    end

    initialize_with { attributes }
  end

  # Task Artifact Update Event factory
  factory :task_artifact_update_event, class: Hash do
    task_id { SecureRandom.uuid }
    context_id { SecureRandom.uuid }
    artifact do
      {
        artifactId: SecureRandom.uuid,
        name: "Generated Artifact",
        parts: [{ kind: "text", text: "Generated content" }]
      }
    end
    append { false }

    trait :appending do
      append { true }
    end

    initialize_with { attributes }
  end

  # Push Notification Config factory
  factory :push_notification_config, class: Hash do
    id { SecureRandom.uuid }
    url { "https://client.example.com/webhook" }
    token { SecureRandom.hex(32) }

    trait :with_auth do
      authentication do
        {
          schemes: ["Bearer"],
          credentials: "bearer_token_here"
        }
      end
    end

    initialize_with { attributes }
  end

  # JSON-RPC Request factory
  factory :json_rpc_request, class: Hash do
    jsonrpc { "2.0" }
    add_attribute(:method) { "message/send" }
    params { {} }
    id { 1 }

    trait :batch do
      # Returns an array for batch requests
      initialize_with { [attributes, attributes.merge(id: 2)] }
    end

    initialize_with { attributes }
  end
end
