# frozen_string_literal: true

##
# A2A Protocol Specification Compliance Test Suite
#
# This test suite validates compliance with the A2A protocol specification,
# including message formats, task lifecycle, agent cards, and all A2A-specific features.
#
RSpec.describe "A2A Protocol Compliance", :compliance do
  describe "Core A2A Methods" do
    context "message/send method" do
      it "accepts valid message/send requests" do
        message = build_message(
          role: "user",
          text: "Hello, agent!"
        )

        request = build_json_rpc_request("message/send", { message: message })

        expect(request).to be_valid_json_rpc_request
        expect(request[:method]).to eq("message/send")
        expect(request[:params][:message]).to be_valid_a2a_message
      end

      it "validates message structure in requests" do
        invalid_message = {
          messageId: test_uuid,
          role: "invalid_role", # Invalid role
          parts: []
        }

        request = build_json_rpc_request("message/send", { message: invalid_message })

        expect(request).to be_valid_json_rpc_request
        expect(request[:params][:message]).not_to be_valid_a2a_message
      end

      it "supports streaming parameter" do
        message = build_message
        request = build_json_rpc_request("message/send", {
                                           message: message,
                                           streaming: true
                                         })

        expect(request[:params][:streaming]).to be true
      end

      it "supports context parameter" do
        message = build_message
        context = { timeout: 30, priority: "high" }

        request = build_json_rpc_request("message/send", {
                                           message: message,
                                           context: context
                                         })

        expect(request[:params][:context]).to eq(context)
      end
    end

    context "message/stream method" do
      it "accepts valid message/stream requests" do
        message = build_message
        request = build_json_rpc_request("message/stream", { message: message })

        expect(request).to be_valid_json_rpc_request
        expect(request[:method]).to eq("message/stream")
      end
    end

    context "tasks/get method" do
      it "accepts valid tasks/get requests" do
        task_id = test_uuid
        request = build_json_rpc_request("tasks/get", { id: task_id })

        expect(request).to be_valid_json_rpc_request
        expect(request[:params][:id]).to eq(task_id)
      end

      it "supports historyLength parameter" do
        request = build_json_rpc_request("tasks/get", {
                                           id: test_uuid,
                                           historyLength: 10
                                         })

        expect(request[:params][:historyLength]).to eq(10)
      end

      it "supports context parameter" do
        request = build_json_rpc_request("tasks/get", {
                                           id: test_uuid,
                                           context: { includeArtifacts: true }
                                         })

        expect(request[:params][:context][:includeArtifacts]).to be true
      end
    end

    context "tasks/cancel method" do
      it "accepts valid tasks/cancel requests" do
        task_id = test_uuid
        request = build_json_rpc_request("tasks/cancel", { id: task_id })

        expect(request).to be_valid_json_rpc_request
        expect(request[:params][:id]).to eq(task_id)
      end

      it "supports reason parameter" do
        request = build_json_rpc_request("tasks/cancel", {
                                           id: test_uuid,
                                           reason: "User requested cancellation"
                                         })

        expect(request[:params][:reason]).to eq("User requested cancellation")
      end
    end

    context "tasks/resubscribe method" do
      it "accepts valid tasks/resubscribe requests" do
        task_id = test_uuid
        request = build_json_rpc_request("tasks/resubscribe", { id: task_id })

        expect(request).to be_valid_json_rpc_request
        expect(request[:params][:id]).to eq(task_id)
      end
    end

    context "agent/getCard method" do
      it "accepts valid agent/getCard requests" do
        request = build_json_rpc_request("agent/getCard", {})

        expect(request).to be_valid_json_rpc_request
        expect(request[:method]).to eq("agent/getCard")
      end

      it "supports context parameter" do
        request = build_json_rpc_request("agent/getCard", {
                                           context: { includeExtended: true }
                                         })

        expect(request[:params][:context][:includeExtended]).to be true
      end
    end

    context "agent/getAuthenticatedExtendedCard method" do
      it "accepts valid authenticated card requests" do
        request = build_json_rpc_request("agent/getAuthenticatedExtendedCard", {})

        expect(request).to be_valid_json_rpc_request
        expect(request[:method]).to eq("agent/getAuthenticatedExtendedCard")
      end
    end
  end

  describe "Push Notification Methods" do
    context "tasks/pushNotificationConfig/set method" do
      it "accepts valid set requests" do
        config = build(:push_notification_config)
        request = build_json_rpc_request("tasks/pushNotificationConfig/set", {
                                           taskId: test_uuid,
                                           pushNotificationConfig: config
                                         })

        expect(request).to be_valid_json_rpc_request
        expect(request[:params][:pushNotificationConfig]).to be_valid_push_notification_config
      end
    end

    context "tasks/pushNotificationConfig/get method" do
      it "accepts valid get requests" do
        request = build_json_rpc_request("tasks/pushNotificationConfig/get", {
                                           taskId: test_uuid,
                                           id: test_uuid
                                         })

        expect(request).to be_valid_json_rpc_request
      end
    end

    context "tasks/pushNotificationConfig/list method" do
      it "accepts valid list requests" do
        request = build_json_rpc_request("tasks/pushNotificationConfig/list", {
                                           taskId: test_uuid
                                         })

        expect(request).to be_valid_json_rpc_request
      end
    end

    context "tasks/pushNotificationConfig/delete method" do
      it "accepts valid delete requests" do
        request = build_json_rpc_request("tasks/pushNotificationConfig/delete", {
                                           taskId: test_uuid,
                                           id: test_uuid
                                         })

        expect(request).to be_valid_json_rpc_request
      end
    end
  end

  describe "Message Format Compliance" do
    context "message structure" do
      it "validates required fields" do
        message = {
          messageId: test_uuid,
          role: "user",
          kind: "message",
          parts: [{ kind: "text", text: "Hello" }]
        }

        expect(message).to be_valid_a2a_message
      end

      it "validates message roles" do
        valid_roles = %w[user agent]

        valid_roles.each do |role|
          message = build_message(role: role)
          expect(message[:role]).to be_valid_message_role
          expect(message).to be_valid_a2a_message
        end
      end

      it "rejects invalid message roles" do
        invalid_message = build_message(role: "invalid")
        expect(invalid_message[:role]).not_to be_valid_message_role
        expect(invalid_message).not_to be_valid_a2a_message
      end

      it "validates part types" do
        valid_parts = [
          { kind: "text", text: "Hello" },
          { kind: "file", file: { name: "test.txt", mimeType: "text/plain", bytes: "dGVzdA==" } },
          { kind: "data", data: { key: "value" } }
        ]

        valid_parts.each do |part|
          message = build_message(parts: [part])
          expect(message).to be_valid_a2a_message
        end
      end

      it "supports optional fields" do
        message = {
          messageId: test_uuid,
          role: "user",
          kind: "message",
          parts: [{ kind: "text", text: "Hello" }],
          contextId: test_uuid,
          taskId: test_uuid,
          metadata: { priority: "high" },
          extensions: [{ uri: "https://example.com/ext", data: {} }],
          referenceTaskIds: [test_uuid]
        }

        expect(message).to be_valid_a2a_message
      end
    end

    context "part validation" do
      it "validates text parts" do
        text_part = { kind: "text", text: "Hello, world!" }
        message = build_message(parts: [text_part])

        expect(message).to be_valid_a2a_message
      end

      it "validates file parts with bytes" do
        file_part = {
          kind: "file",
          file: {
            name: "document.pdf",
            mimeType: "application/pdf",
            bytes: Base64.encode64("fake pdf content")
          }
        }
        message = build_message(parts: [file_part])

        expect(message).to be_valid_a2a_message
      end

      it "validates file parts with URI" do
        file_part = {
          kind: "file",
          file: {
            name: "image.jpg",
            mimeType: "image/jpeg",
            uri: "https://example.com/image.jpg"
          }
        }
        message = build_message(parts: [file_part])

        expect(message).to be_valid_a2a_message
      end

      it "validates data parts" do
        data_part = {
          kind: "data",
          data: {
            type: "analysis_request",
            parameters: { depth: "comprehensive" },
            metadata: { version: "1.0" }
          }
        }
        message = build_message(parts: [data_part])

        expect(message).to be_valid_a2a_message
      end

      it "supports part metadata" do
        part_with_metadata = {
          kind: "text",
          text: "Hello",
          metadata: {
            timestamp: Time.current.iso8601,
            source: "user_input",
            confidence: 0.95
          }
        }
        message = build_message(parts: [part_with_metadata])

        expect(message).to be_valid_a2a_message
      end
    end
  end

  describe "Task Format Compliance" do
    context "task structure" do
      it "validates required fields" do
        task = {
          id: test_uuid,
          contextId: test_uuid,
          kind: "task",
          status: {
            state: "submitted",
            updatedAt: Time.current.iso8601
          }
        }

        expect(task).to be_valid_a2a_task
      end

      it "validates task states" do
        valid_states = %w[
          submitted working input-required completed
          canceled failed rejected auth-required unknown
        ]

        valid_states.each do |state|
          expect(state).to be_valid_task_state

          task = build_task(state: state)
          expect(task).to be_valid_a2a_task
        end
      end

      it "supports optional task fields" do
        task = {
          id: test_uuid,
          contextId: test_uuid,
          kind: "task",
          status: {
            state: "completed",
            message: "Task completed successfully",
            progress: 100,
            result: { output: "success" },
            updatedAt: Time.current.iso8601
          },
          artifacts: [
            {
              artifactId: test_uuid,
              name: "Result",
              parts: [{ kind: "text", text: "Output" }]
            }
          ],
          history: [build_message],
          metadata: { priority: "high" }
        }

        expect(task).to be_valid_a2a_task
      end
    end

    context "task status validation" do
      it "validates status structure" do
        status = {
          state: "working",
          message: "Processing request",
          progress: 50,
          updatedAt: Time.current.iso8601
        }

        task = build_task(status: status)
        expect(task).to be_valid_a2a_task
      end

      it "validates completed status with result" do
        status = {
          state: "completed",
          result: {
            summary: "Analysis complete",
            data: { items: 42 }
          },
          updatedAt: Time.current.iso8601
        }

        task = build_task(status: status)
        expect(task).to be_valid_a2a_task
      end

      it "validates failed status with error" do
        status = {
          state: "failed",
          error: {
            code: "PROCESSING_ERROR",
            message: "Failed to process input",
            details: { step: "validation" }
          },
          updatedAt: Time.current.iso8601
        }

        task = build_task(status: status)
        expect(task).to be_valid_a2a_task
      end
    end
  end

  describe "Agent Card Compliance" do
    context "agent card structure" do
      it "validates minimal agent card" do
        card = generate_minimal_agent_card
        expect(card).to be_valid_agent_card
      end

      it "validates comprehensive agent card" do
        card = generate_full_agent_card
        expect(card).to be_valid_agent_card
      end

      it "validates required fields" do
        required_fields = %w[
          name description version url preferredTransport
          skills capabilities defaultInputModes defaultOutputModes
        ]

        card = build_agent_card
        required_fields.each do |field|
          expect(card).to have_key(field)
        end
      end

      it "validates transport protocols" do
        valid_transports = ["JSONRPC", "GRPC", "HTTP+JSON"]

        valid_transports.each do |transport|
          expect(transport).to be_valid_transport

          card = build_agent_card(preferredTransport: transport)
          expect(card).to be_valid_agent_card
        end
      end

      it "validates additional interfaces" do
        card = build_agent_card(
          additionalInterfaces: [
            { transport: "GRPC", url: "grpc://example.com:443" },
            { transport: "HTTP+JSON", url: "https://example.com/rest" }
          ]
        )

        expect(card).to be_valid_agent_card
      end
    end

    context "skill validation" do
      it "validates skill structure" do
        skill = {
          id: "text_analysis",
          name: "Text Analysis",
          description: "Analyze text content",
          tags: %w[nlp analysis],
          examples: ["Analyze sentiment", "Extract entities"],
          inputModes: ["text/plain"],
          outputModes: ["application/json"]
        }

        card = build_agent_card(skills: [skill])
        expect(card).to be_valid_agent_card
      end

      it "validates skill security requirements" do
        skill = {
          id: "secure_skill",
          name: "Secure Skill",
          description: "A skill requiring authentication",
          security: [{ "oauth2" => %w[read write] }]
        }

        card = build_agent_card(skills: [skill])
        expect(card).to be_valid_agent_card
      end
    end

    context "capabilities validation" do
      it "validates capability flags" do
        capabilities = {
          streaming: true,
          pushNotifications: true,
          stateTransitionHistory: false,
          extensions: ["https://example.com/ext/v1"]
        }

        card = build_agent_card(capabilities: capabilities)
        expect(card).to be_valid_agent_card
      end
    end

    context "security scheme validation" do
      it "validates OAuth2 security scheme" do
        security_scheme = {
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

        card = build_agent_card(securitySchemes: security_scheme)
        expect(card).to be_valid_agent_card
      end

      it "validates API key security scheme" do
        security_scheme = {
          "apiKey" => {
            type: "apiKey",
            name: "X-API-Key",
            in: "header"
          }
        }

        card = build_agent_card(securitySchemes: security_scheme)
        expect(card).to be_valid_agent_card
      end
    end
  end

  describe "Event Format Compliance" do
    context "task status update events" do
      it "validates task status update event structure" do
        event = {
          taskId: test_uuid,
          contextId: test_uuid,
          status: {
            state: "working",
            progress: 25,
            updatedAt: Time.current.iso8601
          }
        }

        expect(event).to be_valid_task_status_update_event
      end
    end

    context "task artifact update events" do
      it "validates task artifact update event structure" do
        event = {
          taskId: test_uuid,
          contextId: test_uuid,
          artifact: {
            artifactId: test_uuid,
            name: "Progress Report",
            parts: [{ kind: "text", text: "25% complete" }]
          },
          append: false
        }

        expect(event).to be_valid_task_artifact_update_event
      end

      it "validates artifact append events" do
        event = {
          taskId: test_uuid,
          contextId: test_uuid,
          artifact: {
            artifactId: test_uuid,
            parts: [{ kind: "text", text: "Additional content..." }]
          },
          append: true
        }

        expect(event).to be_valid_task_artifact_update_event
      end
    end
  end

  describe "Error Code Compliance" do
    it "uses correct A2A error codes" do
      a2a_errors = {
        A2A::Protocol::JsonRpc::TASK_NOT_FOUND => "Task not found",
        A2A::Protocol::JsonRpc::TASK_NOT_CANCELABLE => "Task cannot be canceled",
        A2A::Protocol::JsonRpc::INVALID_TASK_STATE => "Invalid task state",
        A2A::Protocol::JsonRpc::AUTHENTICATION_REQUIRED => "Authentication required",
        A2A::Protocol::JsonRpc::AUTHORIZATION_FAILED => "Authorization failed",
        A2A::Protocol::JsonRpc::RATE_LIMIT_EXCEEDED => "Rate limit exceeded",
        A2A::Protocol::JsonRpc::AGENT_UNAVAILABLE => "Agent unavailable",
        A2A::Protocol::JsonRpc::PROTOCOL_VERSION_MISMATCH => "Protocol version mismatch",
        A2A::Protocol::JsonRpc::CAPABILITY_NOT_SUPPORTED => "Capability not supported",
        A2A::Protocol::JsonRpc::RESOURCE_EXHAUSTED => "Resource exhausted"
      }

      a2a_errors.each do |code, message|
        error_response = create_json_rpc_error(code: code, message: message)
        expect(error_response).to have_a2a_error(code)
      end
    end
  end

  describe "Extension Support" do
    it "validates extension format in messages" do
      extension = {
        uri: "https://example.com/extensions/timestamp/v1",
        data: {
          clientTimestamp: Time.current.iso8601,
          timezone: "UTC"
        }
      }

      message = build_message(extensions: [extension])
      expect(message).to be_valid_a2a_message
    end

    it "validates extension format in agent cards" do
      card = build_agent_card(
        capabilities: {
          extensions: ["https://example.com/extensions/traceability/v1"]
        }
      )

      expect(card).to be_valid_agent_card
    end
  end

  describe "Protocol Version Compliance" do
    it "supports protocol version 0.3.0" do
      card = build_agent_card(protocolVersion: "0.3.0")
      expect(card).to be_valid_agent_card
    end

    it "includes protocol version in agent cards" do
      card = generate_full_agent_card
      expect(card).to have_key(:protocolVersion)
      expect(card[:protocolVersion]).to match(/\d+\.\d+\.\d+/)
    end
  end
end
