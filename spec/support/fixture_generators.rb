# frozen_string_literal: true

##
# Fixture generators for A2A protocol testing
# Provides methods to generate realistic test data and fixtures
#
module A2AFixtureGenerators
  # Agent card fixtures

  # Generate a comprehensive agent card with all optional fields
  def generate_full_agent_card(**overrides)
    {
      name: "Advanced Test Agent",
      description: "A comprehensive test agent with all A2A protocol features",
      version: "2.1.0",
      url: "https://advanced-agent.example.com/a2a",
      preferredTransport: "JSONRPC",
      protocolVersion: "0.3.0",

      skills: [
        {
          id: "text_processing",
          name: "Text Processing",
          description: "Advanced text analysis and processing capabilities",
          tags: %w[nlp text analysis],
          examples: [
            "Analyze the sentiment of this text",
            "Summarize this document",
            "Extract key entities from this content"
          ],
          inputModes: ["text/plain", "text/markdown", "application/json"],
          outputModes: ["text/plain", "application/json"],
          security: [{ "oauth2" => %w[read write] }]
        },
        {
          id: "file_processing",
          name: "File Processing",
          description: "Process and analyze various file formats",
          tags: %w[files processing conversion],
          examples: [
            "Convert PDF to text",
            "Extract metadata from images",
            "Process CSV data"
          ],
          inputModes: ["application/pdf", "image/*", "text/csv"],
          outputModes: ["text/plain", "application/json"],
          security: [{ "apiKey" => [] }]
        }
      ],

      capabilities: {
        streaming: true,
        pushNotifications: true,
        stateTransitionHistory: true,
        extensions: ["https://example.com/extensions/timestamp/v1"]
      },

      defaultInputModes: ["text/plain", "application/json"],
      defaultOutputModes: ["text/plain", "application/json"],

      additionalInterfaces: [
        {
          transport: "GRPC",
          url: "grpc://advanced-agent.example.com:443"
        },
        {
          transport: "HTTP+JSON",
          url: "https://advanced-agent.example.com/rest"
        }
      ],

      security: [
        { "oauth2" => %w[read write admin] },
        { "apiKey" => [] }
      ],

      securitySchemes: {
        "oauth2" => {
          type: "oauth2",
          flows: {
            clientCredentials: {
              tokenUrl: "https://auth.example.com/oauth/token",
              scopes: {
                "read" => "Read access to agent capabilities",
                "write" => "Write access for task creation",
                "admin" => "Administrative access"
              }
            },
            authorizationCode: {
              authorizationUrl: "https://auth.example.com/oauth/authorize",
              tokenUrl: "https://auth.example.com/oauth/token",
              scopes: {
                "read" => "Read access to agent capabilities",
                "write" => "Write access for task creation"
              }
            }
          }
        },
        "apiKey" => {
          type: "apiKey",
          name: "X-API-Key",
          in: "header"
        }
      },

      provider: {
        name: "Example Corp",
        url: "https://example.com",
        email: "support@example.com"
      },

      supportsAuthenticatedExtendedCard: true,

      signatures: [
        {
          keyId: "key-1",
          algorithm: "RS256",
          signature: "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."
        }
      ],

      documentationUrl: "https://docs.example.com/agent-api",
      iconUrl: "https://example.com/icons/agent.png",

      metadata: {
        createdAt: "2024-01-01T00:00:00Z",
        updatedAt: Time.current.iso8601,
        version: "2.1.0",
        environment: "production"
      }
    }.deep_merge(overrides)
  end

  # Generate a minimal agent card with only required fields
  def generate_minimal_agent_card(**overrides)
    {
      name: "Minimal Agent",
      description: "A minimal test agent",
      version: "1.0.0",
      url: "https://minimal-agent.example.com/a2a",
      preferredTransport: "JSONRPC",
      skills: [],
      capabilities: {},
      defaultInputModes: ["text/plain"],
      defaultOutputModes: ["text/plain"]
    }.merge(overrides)
  end

  # Message fixtures

  # Generate a complex message with multiple parts
  def generate_complex_message(**overrides)
    {
      messageId: test_uuid,
      role: "user",
      kind: "message",
      contextId: test_uuid,
      taskId: test_uuid,

      parts: [
        {
          kind: "text",
          text: "Please analyze this document and the attached image:",
          metadata: {
            timestamp: Time.current.iso8601,
            source: "user_input"
          }
        },
        {
          kind: "file",
          file: {
            name: "document.pdf",
            mimeType: "application/pdf",
            bytes: Base64.encode64("Mock PDF content for testing"),
            uri: "https://example.com/files/document.pdf"
          },
          metadata: {
            fileSize: 1024,
            uploadedAt: Time.current.iso8601
          }
        },
        {
          kind: "file",
          file: {
            name: "chart.png",
            mimeType: "image/png",
            bytes: Base64.encode64("Mock PNG content for testing")
          },
          metadata: {
            dimensions: { width: 800, height: 600 },
            fileSize: 2048
          }
        },
        {
          kind: "data",
          data: {
            analysisType: "comprehensive",
            outputFormat: "json",
            includeMetadata: true
          },
          metadata: {
            schemaVersion: "1.0"
          }
        }
      ],

      metadata: {
        priority: "high",
        timeout: 300,
        clientVersion: "1.2.3",
        userAgent: "TestClient/1.0"
      },

      extensions: [
        {
          uri: "https://example.com/extensions/timestamp/v1",
          data: {
            clientTimestamp: Time.current.iso8601,
            timezone: "UTC"
          }
        }
      ],

      referenceTaskIds: [test_uuid, test_uuid]
    }.deep_merge(overrides)
  end

  # Generate a streaming message response
  def generate_streaming_message_response(**overrides)
    base_message = {
      messageId: test_uuid,
      role: "agent",
      kind: "message",
      contextId: overrides[:contextId] || test_uuid,
      taskId: overrides[:taskId] || test_uuid
    }

    # Generate multiple message parts for streaming
    [
      base_message.merge(
        parts: [{ kind: "text", text: "Starting analysis..." }],
        metadata: { streamIndex: 0, isPartial: true }
      ),
      base_message.merge(
        messageId: test_uuid,
        parts: [{ kind: "text", text: "Processing document..." }],
        metadata: { streamIndex: 1, isPartial: true }
      ),
      base_message.merge(
        messageId: test_uuid,
        parts: [
          { kind: "text", text: "Analysis complete. Here are the results:" },
          {
            kind: "data",
            data: {
              summary: "Document contains financial data",
              entities: ["Company A", "Q4 2023", "$1.2M"],
              sentiment: "neutral"
            }
          }
        ],
        metadata: { streamIndex: 2, isPartial: false, isFinal: true }
      )
    ]
  end

  # Task fixtures

  # Generate a comprehensive task with full lifecycle
  def generate_comprehensive_task(**overrides)
    task_id = test_uuid
    context_id = test_uuid

    {
      id: task_id,
      contextId: context_id,
      kind: "task",

      status: {
        state: "completed",
        message: "Task completed successfully",
        progress: 100,
        result: {
          summary: "Analysis completed",
          processingTime: 45.2,
          itemsProcessed: 150
        },
        updatedAt: Time.current.iso8601
      },

      artifacts: [
        {
          artifactId: test_uuid,
          name: "Analysis Report",
          description: "Comprehensive analysis results",
          parts: [
            {
              kind: "text",
              text: "# Analysis Report\n\nThis document contains the complete analysis results..."
            },
            {
              kind: "file",
              file: {
                name: "detailed_report.json",
                mimeType: "application/json",
                bytes: Base64.encode64({
                  analysis: {
                    totalItems: 150,
                    categories: %w[financial operational strategic],
                    confidence: 0.95
                  }
                }.to_json)
              }
            }
          ],
          metadata: {
            generatedAt: Time.current.iso8601,
            version: "1.0",
            format: "mixed"
          }
        },
        {
          artifactId: test_uuid,
          name: "Processing Log",
          description: "Detailed processing log",
          parts: [
            {
              kind: "text",
              text: "2024-01-01 10:00:00 - Started processing\n2024-01-01 10:00:45 - Completed processing"
            }
          ]
        }
      ],

      history: [
        generate_complex_message(
          role: "user",
          contextId: context_id,
          taskId: task_id
        ),
        {
          messageId: test_uuid,
          role: "agent",
          kind: "message",
          contextId: context_id,
          taskId: task_id,
          parts: [
            { kind: "text", text: "I'll analyze the document for you." }
          ],
          metadata: { timestamp: Time.current.iso8601 }
        }
      ],

      metadata: {
        createdAt: 1.hour.ago.iso8601,
        updatedAt: Time.current.iso8601,
        priority: "high",
        estimatedDuration: 60,
        actualDuration: 45.2,
        resourcesUsed: {
          cpu: "2.5 cores",
          memory: "1.2 GB",
          storage: "500 MB"
        }
      }
    }.deep_merge(overrides)
  end

  # Generate task status update events for streaming
  def generate_task_status_events(task_id:, context_id:)
    states = %w[submitted working completed]

    states.map.with_index do |state, index|
      {
        taskId: task_id,
        contextId: context_id,
        status: {
          state: state,
          message: "Task is #{state}",
          progress: (index + 1) * 33,
          updatedAt: (Time.current + index.minutes).iso8601
        },
        metadata: {
          eventIndex: index,
          timestamp: (Time.current + index.minutes).iso8601
        }
      }
    end
  end

  # Generate task artifact update events
  def generate_artifact_update_events(task_id:, context_id:, artifact_id: nil)
    artifact_id ||= test_uuid

    [
      {
        taskId: task_id,
        contextId: context_id,
        artifact: {
          artifactId: artifact_id,
          name: "Streaming Results",
          parts: [
            { kind: "text", text: "Starting analysis..." }
          ]
        },
        append: false,
        metadata: { eventIndex: 0 }
      },
      {
        taskId: task_id,
        contextId: context_id,
        artifact: {
          artifactId: artifact_id,
          parts: [
            { kind: "text", text: "\nProcessing item 1 of 10..." }
          ]
        },
        append: true,
        metadata: { eventIndex: 1 }
      },
      {
        taskId: task_id,
        contextId: context_id,
        artifact: {
          artifactId: artifact_id,
          parts: [
            { kind: "text", text: "\nAnalysis complete!" },
            {
              kind: "data",
              data: { result: "success", itemsProcessed: 10 }
            }
          ]
        },
        append: true,
        metadata: { eventIndex: 2, isFinal: true }
      }
    ]
  end

  # Push notification fixtures

  # Generate push notification configurations
  def generate_push_notification_configs(count: 3)
    (1..count).map do |i|
      {
        id: test_uuid,
        url: "https://client#{i}.example.com/webhook",
        token: test_auth_token,
        authentication: {
          schemes: ["Bearer"],
          credentials: "webhook_token_#{i}"
        },
        metadata: {
          createdAt: Time.current.iso8601,
          description: "Webhook endpoint #{i}",
          retryPolicy: {
            maxRetries: 3,
            backoffMultiplier: 2
          }
        }
      }
    end
  end

  # Error fixtures

  # Generate various JSON-RPC error responses
  def generate_json_rpc_errors
    {
      parse_error: {
        jsonrpc: "2.0",
        error: {
          code: -32_700,
          message: "Parse error",
          data: "Invalid JSON was received by the server"
        },
        id: nil
      },

      invalid_request: {
        jsonrpc: "2.0",
        error: {
          code: -32_600,
          message: "Invalid Request",
          data: "The JSON sent is not a valid Request object"
        },
        id: nil
      },

      method_not_found: {
        jsonrpc: "2.0",
        error: {
          code: -32_601,
          message: "Method not found",
          data: "The method does not exist / is not available"
        },
        id: 1
      },

      task_not_found: {
        jsonrpc: "2.0",
        error: {
          code: -32_001,
          message: "Task not found",
          data: { taskId: test_uuid }
        },
        id: 1
      },

      authentication_required: {
        jsonrpc: "2.0",
        error: {
          code: -32_004,
          message: "Authentication required",
          data: {
            supportedSchemes: %w[Bearer ApiKey],
            authUrl: "https://auth.example.com"
          }
        },
        id: 1
      }
    }
  end

  # Performance test fixtures

  # Generate load test scenarios
  def generate_load_test_scenarios
    {
      light_load: {
        concurrent_users: 10,
        duration: 30.seconds,
        request_rate: 5, # requests per second per user
        message_size: :small
      },

      medium_load: {
        concurrent_users: 50,
        duration: 2.minutes,
        request_rate: 10,
        message_size: :medium
      },

      heavy_load: {
        concurrent_users: 100,
        duration: 5.minutes,
        request_rate: 20,
        message_size: :large
      },

      stress_test: {
        concurrent_users: 200,
        duration: 10.minutes,
        request_rate: 50,
        message_size: :mixed
      }
    }
  end

  # Generate messages of different sizes for performance testing
  def generate_sized_message(size: :medium)
    base_text = "This is a test message for performance testing. "

    text_content = case size
                   when :small
                     base_text * 10 # ~500 chars
                   when :medium
                     base_text * 100 # ~5KB
                   when :large
                     base_text * 1000 # ~50KB
                   when :mixed
                     base_text * rand(10..1000)
                   else
                     base_text * 100
                   end

    {
      messageId: test_uuid,
      role: "user",
      kind: "message",
      parts: [
        { kind: "text", text: text_content }
      ],
      metadata: {
        size: size,
        characterCount: text_content.length,
        generatedAt: Time.current.iso8601
      }
    }
  end

  # Compliance test fixtures

  # Generate test cases for protocol compliance
  def generate_compliance_test_cases
    {
      valid_requests: [
        build_json_rpc_request("message/send", { message: build_message }),
        build_json_rpc_request("tasks/get", { id: test_uuid }),
        build_json_rpc_request("agent/getCard", {})
      ],

      invalid_requests: [
        { jsonrpc: "1.0", method: "test" }, # Wrong version
        { jsonrpc: "2.0" }, # Missing method
        { jsonrpc: "2.0", method: 123 }, # Invalid method type
        { jsonrpc: "2.0", method: "test", params: "invalid" } # Invalid params
      ],

      batch_requests: [
        [
          build_json_rpc_request("message/send", { message: build_message }, 1),
          build_json_rpc_request("tasks/get", { id: test_uuid }, 2)
        ]
      ],

      notifications: [
        { jsonrpc: "2.0", method: "notification/test", params: {} }
      ]
    }
  end

  # File helpers for fixture management

  # Save generated fixtures to files
  def save_fixtures_to_files(fixtures_dir: "spec/fixtures/generated")
    FileUtils.mkdir_p(fixtures_dir)

    fixtures = {
      "agent_cards.json" => {
        full: generate_full_agent_card,
        minimal: generate_minimal_agent_card
      },

      "messages.json" => {
        complex: generate_complex_message,
        streaming: generate_streaming_message_response
      },

      "tasks.json" => {
        comprehensive: generate_comprehensive_task,
        status_events: generate_task_status_events(
          task_id: test_uuid,
          context_id: test_uuid
        )
      },

      "errors.json" => generate_json_rpc_errors,

      "compliance_cases.json" => generate_compliance_test_cases,

      "load_scenarios.json" => generate_load_test_scenarios
    }

    fixtures.each do |filename, data|
      File.write(
        File.join(fixtures_dir, filename),
        JSON.pretty_generate(data)
      )
    end

    puts "Generated fixtures saved to #{fixtures_dir}"
  end

  # Load fixtures from files
  def load_fixtures_from_files(fixtures_dir: "spec/fixtures/generated")
    fixtures = {}

    Dir.glob(File.join(fixtures_dir, "*.json")).each do |file|
      key = File.basename(file, ".json")
      fixtures[key] = JSON.parse(File.read(file))
    end

    fixtures
  end
end

RSpec.configure do |config|
  config.include A2AFixtureGenerators
end
