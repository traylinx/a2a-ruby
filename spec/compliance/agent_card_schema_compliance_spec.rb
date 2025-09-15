# frozen_string_literal: true

##
# Agent Card Schema Compliance Test Suite
#
# This test suite validates complete compliance with the A2A Agent Card schema,
# including all required and optional fields, security schemes, and validation rules.
#
RSpec.describe "Agent Card Schema Compliance", :compliance do
  describe "Required Fields Validation" do
    let(:minimal_required_fields) do
      {
        name: "Test Agent",
        description: "A test agent",
        version: "1.0.0",
        url: "https://example.com/a2a",
        preferredTransport: "JSONRPC",
        skills: [],
        capabilities: {},
        defaultInputModes: ["text/plain"],
        defaultOutputModes: ["text/plain"]
      }
    end

    it "validates agent card with all required fields" do
      card = minimal_required_fields
      expect(card).to be_valid_agent_card
    end

    it "rejects agent card missing name" do
      card = minimal_required_fields.except(:name)
      expect(card).not_to be_valid_agent_card
    end

    it "rejects agent card missing description" do
      card = minimal_required_fields.except(:description)
      expect(card).not_to be_valid_agent_card
    end

    it "rejects agent card missing version" do
      card = minimal_required_fields.except(:version)
      expect(card).not_to be_valid_agent_card
    end

    it "rejects agent card missing url" do
      card = minimal_required_fields.except(:url)
      expect(card).not_to be_valid_agent_card
    end

    it "rejects agent card missing preferredTransport" do
      card = minimal_required_fields.except(:preferredTransport)
      expect(card).not_to be_valid_agent_card
    end

    it "rejects agent card missing skills" do
      card = minimal_required_fields.except(:skills)
      expect(card).not_to be_valid_agent_card
    end

    it "rejects agent card missing capabilities" do
      card = minimal_required_fields.except(:capabilities)
      expect(card).not_to be_valid_agent_card
    end

    it "rejects agent card missing defaultInputModes" do
      card = minimal_required_fields.except(:defaultInputModes)
      expect(card).not_to be_valid_agent_card
    end

    it "rejects agent card missing defaultOutputModes" do
      card = minimal_required_fields.except(:defaultOutputModes)
      expect(card).not_to be_valid_agent_card
    end
  end

  describe "Field Type Validation" do
    let(:base_card) { generate_minimal_agent_card }

    it "validates string fields" do
      string_fields = [:name, :description, :version, :url, :preferredTransport]
      
      string_fields.each do |field|
        # Valid string
        card = base_card.merge(field => "valid string")
        expect(card).to be_valid_agent_card
        
        # Invalid non-string
        invalid_card = base_card.merge(field => 123)
        expect(invalid_card).not_to be_valid_agent_card
      end
    end

    it "validates array fields" do
      array_fields = [:skills, :defaultInputModes, :defaultOutputModes]
      
      array_fields.each do |field|
        # Valid array
        card = base_card.merge(field => ["item1", "item2"])
        expect(card).to be_valid_agent_card
        
        # Invalid non-array
        invalid_card = base_card.merge(field => "not an array")
        expect(invalid_card).not_to be_valid_agent_card
      end
    end

    it "validates object fields" do
      # Valid capabilities object
      card = base_card.merge(capabilities: { streaming: true })
      expect(card).to be_valid_agent_card
      
      # Invalid non-object capabilities
      invalid_card = base_card.merge(capabilities: "not an object")
      expect(invalid_card).not_to be_valid_agent_card
    end
  end

  describe "Transport Protocol Validation" do
    let(:base_card) { generate_minimal_agent_card }

    it "accepts valid transport protocols" do
      valid_transports = ["JSONRPC", "GRPC", "HTTP+JSON"]
      
      valid_transports.each do |transport|
        card = base_card.merge(preferredTransport: transport)
        expect(card).to be_valid_agent_card
        expect(transport).to be_valid_transport
      end
    end

    it "rejects invalid transport protocols" do
      invalid_transports = ["HTTP", "REST", "WEBSOCKET", "invalid"]
      
      invalid_transports.each do |transport|
        card = base_card.merge(preferredTransport: transport)
        expect(card).not_to be_valid_agent_card
        expect(transport).not_to be_valid_transport
      end
    end
  end

  describe "Skills Validation" do
    let(:base_card) { generate_minimal_agent_card }

    context "skill structure" do
      it "validates complete skill objects" do
        skill = {
          id: "text_processing",
          name: "Text Processing",
          description: "Process and analyze text content",
          tags: ["nlp", "text", "analysis"],
          examples: [
            "Analyze the sentiment of this text",
            "Extract key entities from this document"
          ],
          inputModes: ["text/plain", "text/markdown"],
          outputModes: ["application/json", "text/plain"],
          security: [{ "oauth2" => ["read"] }]
        }
        
        card = base_card.merge(skills: [skill])
        expect(card).to be_valid_agent_card
      end

      it "validates minimal skill objects" do
        skill = {
          id: "minimal_skill",
          name: "Minimal Skill",
          description: "A minimal skill"
        }
        
        card = base_card.merge(skills: [skill])
        expect(card).to be_valid_agent_card
      end

      it "rejects skills missing required fields" do
        incomplete_skills = [
          { name: "Missing ID", description: "No ID field" },
          { id: "missing_name", description: "No name field" },
          { id: "missing_desc", name: "Missing Description" }
        ]
        
        incomplete_skills.each do |skill|
          card = base_card.merge(skills: [skill])
          expect(card).not_to be_valid_agent_card
        end
      end

      it "validates skill arrays and objects" do
        skill = {
          id: "array_validation",
          name: "Array Validation",
          description: "Test arrays",
          tags: ["tag1", "tag2"],
          examples: ["example1", "example2"],
          inputModes: ["text/plain"],
          outputModes: ["application/json"]
        }
        
        card = base_card.merge(skills: [skill])
        expect(card).to be_valid_agent_card
      end
    end

    context "skill security" do
      it "validates OAuth2 security requirements" do
        skill = {
          id: "secure_skill",
          name: "Secure Skill",
          description: "Requires OAuth2",
          security: [{ "oauth2" => ["read", "write"] }]
        }
        
        card = base_card.merge(skills: [skill])
        expect(card).to be_valid_agent_card
      end

      it "validates API key security requirements" do
        skill = {
          id: "api_key_skill",
          name: "API Key Skill",
          description: "Requires API key",
          security: [{ "apiKey" => [] }]
        }
        
        card = base_card.merge(skills: [skill])
        expect(card).to be_valid_agent_card
      end

      it "validates multiple security requirements" do
        skill = {
          id: "multi_auth_skill",
          name: "Multi Auth Skill",
          description: "Multiple auth options",
          security: [
            { "oauth2" => ["read"] },
            { "apiKey" => [] }
          ]
        }
        
        card = base_card.merge(skills: [skill])
        expect(card).to be_valid_agent_card
      end
    end
  end

  describe "Capabilities Validation" do
    let(:base_card) { generate_minimal_agent_card }

    it "validates boolean capability flags" do
      capabilities = {
        streaming: true,
        pushNotifications: false,
        stateTransitionHistory: true
      }
      
      card = base_card.merge(capabilities: capabilities)
      expect(card).to be_valid_agent_card
    end

    it "validates extensions array" do
      capabilities = {
        extensions: [
          "https://example.com/extensions/timestamp/v1",
          "https://example.com/extensions/traceability/v1"
        ]
      }
      
      card = base_card.merge(capabilities: capabilities)
      expect(card).to be_valid_agent_card
    end

    it "validates empty capabilities object" do
      card = base_card.merge(capabilities: {})
      expect(card).to be_valid_agent_card
    end

    it "validates comprehensive capabilities" do
      capabilities = {
        streaming: true,
        pushNotifications: true,
        stateTransitionHistory: true,
        extensions: ["https://example.com/ext/v1"],
        customCapability: "custom_value"
      }
      
      card = base_card.merge(capabilities: capabilities)
      expect(card).to be_valid_agent_card
    end
  end

  describe "Additional Interfaces Validation" do
    let(:base_card) { generate_minimal_agent_card }

    it "validates additional interface structure" do
      interfaces = [
        { transport: "GRPC", url: "grpc://example.com:443" },
        { transport: "HTTP+JSON", url: "https://example.com/rest" }
      ]
      
      card = base_card.merge(additionalInterfaces: interfaces)
      expect(card).to be_valid_agent_card
    end

    it "validates interface transport protocols" do
      valid_interfaces = [
        { transport: "JSONRPC", url: "https://example.com/jsonrpc" },
        { transport: "GRPC", url: "grpc://example.com:443" },
        { transport: "HTTP+JSON", url: "https://example.com/rest" }
      ]
      
      valid_interfaces.each do |interface|
        card = base_card.merge(additionalInterfaces: [interface])
        expect(card).to be_valid_agent_card
      end
    end

    it "rejects interfaces with invalid transport" do
      invalid_interface = { transport: "INVALID", url: "https://example.com" }
      card = base_card.merge(additionalInterfaces: [invalid_interface])
      expect(card).not_to be_valid_agent_card
    end

    it "validates interface URLs" do
      interfaces = [
        { transport: "JSONRPC", url: "https://secure.example.com/a2a" },
        { transport: "GRPC", url: "grpc://grpc.example.com:443" },
        { transport: "HTTP+JSON", url: "http://localhost:8080/api" }
      ]
      
      card = base_card.merge(additionalInterfaces: interfaces)
      expect(card).to be_valid_agent_card
    end
  end

  describe "Security Schemes Validation" do
    let(:base_card) { generate_minimal_agent_card }

    context "OAuth2 security scheme" do
      it "validates client credentials flow" do
        security_schemes = {
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
        
        card = base_card.merge(securitySchemes: security_schemes)
        expect(card).to be_valid_agent_card
      end

      it "validates authorization code flow" do
        security_schemes = {
          "oauth2" => {
            type: "oauth2",
            flows: {
              authorizationCode: {
                authorizationUrl: "https://auth.example.com/authorize",
                tokenUrl: "https://auth.example.com/token",
                scopes: {
                  "read" => "Read access",
                  "write" => "Write access"
                }
              }
            }
          }
        }
        
        card = base_card.merge(securitySchemes: security_schemes)
        expect(card).to be_valid_agent_card
      end

      it "validates multiple OAuth2 flows" do
        security_schemes = {
          "oauth2" => {
            type: "oauth2",
            flows: {
              clientCredentials: {
                tokenUrl: "https://auth.example.com/token",
                scopes: { "read" => "Read access" }
              },
              authorizationCode: {
                authorizationUrl: "https://auth.example.com/authorize",
                tokenUrl: "https://auth.example.com/token",
                scopes: { "read" => "Read access", "write" => "Write access" }
              }
            }
          }
        }
        
        card = base_card.merge(securitySchemes: security_schemes)
        expect(card).to be_valid_agent_card
      end
    end

    context "API Key security scheme" do
      it "validates header API key" do
        security_schemes = {
          "apiKey" => {
            type: "apiKey",
            name: "X-API-Key",
            in: "header"
          }
        }
        
        card = base_card.merge(securitySchemes: security_schemes)
        expect(card).to be_valid_agent_card
      end

      it "validates query parameter API key" do
        security_schemes = {
          "apiKey" => {
            type: "apiKey",
            name: "api_key",
            in: "query"
          }
        }
        
        card = base_card.merge(securitySchemes: security_schemes)
        expect(card).to be_valid_agent_card
      end
    end

    context "HTTP authentication scheme" do
      it "validates basic HTTP auth" do
        security_schemes = {
          "httpBasic" => {
            type: "http",
            scheme: "basic"
          }
        }
        
        card = base_card.merge(securitySchemes: security_schemes)
        expect(card).to be_valid_agent_card
      end

      it "validates bearer HTTP auth" do
        security_schemes = {
          "httpBearer" => {
            type: "http",
            scheme: "bearer",
            bearerFormat: "JWT"
          }
        }
        
        card = base_card.merge(securitySchemes: security_schemes)
        expect(card).to be_valid_agent_card
      end
    end

    context "OpenID Connect scheme" do
      it "validates OpenID Connect" do
        security_schemes = {
          "openIdConnect" => {
            type: "openIdConnect",
            openIdConnectUrl: "https://auth.example.com/.well-known/openid_configuration"
          }
        }
        
        card = base_card.merge(securitySchemes: security_schemes)
        expect(card).to be_valid_agent_card
      end
    end

    context "Mutual TLS scheme" do
      it "validates mutual TLS" do
        security_schemes = {
          "mutualTLS" => {
            type: "mutualTLS"
          }
        }
        
        card = base_card.merge(securitySchemes: security_schemes)
        expect(card).to be_valid_agent_card
      end
    end

    context "multiple security schemes" do
      it "validates multiple security schemes" do
        security_schemes = {
          "oauth2" => {
            type: "oauth2",
            flows: {
              clientCredentials: {
                tokenUrl: "https://auth.example.com/token",
                scopes: { "read" => "Read access" }
              }
            }
          },
          "apiKey" => {
            type: "apiKey",
            name: "X-API-Key",
            in: "header"
          },
          "httpBearer" => {
            type: "http",
            scheme: "bearer"
          }
        }
        
        card = base_card.merge(securitySchemes: security_schemes)
        expect(card).to be_valid_agent_card
      end
    end
  end

  describe "Security Requirements Validation" do
    let(:base_card) { generate_minimal_agent_card }

    it "validates OAuth2 security requirements" do
      security = [{ "oauth2" => ["read", "write"] }]
      card = base_card.merge(security: security)
      expect(card).to be_valid_agent_card
    end

    it "validates API key security requirements" do
      security = [{ "apiKey" => [] }]
      card = base_card.merge(security: security)
      expect(card).to be_valid_agent_card
    end

    it "validates multiple security requirements (OR logic)" do
      security = [
        { "oauth2" => ["read"] },
        { "apiKey" => [] }
      ]
      card = base_card.merge(security: security)
      expect(card).to be_valid_agent_card
    end

    it "validates combined security requirements (AND logic)" do
      security = [{ "oauth2" => ["read"], "apiKey" => [] }]
      card = base_card.merge(security: security)
      expect(card).to be_valid_agent_card
    end
  end

  describe "Optional Fields Validation" do
    let(:base_card) { generate_minimal_agent_card }

    it "validates provider information" do
      provider = {
        name: "Example Corp",
        url: "https://example.com",
        email: "support@example.com"
      }
      
      card = base_card.merge(provider: provider)
      expect(card).to be_valid_agent_card
    end

    it "validates protocol version" do
      card = base_card.merge(protocolVersion: "0.3.0")
      expect(card).to be_valid_agent_card
    end

    it "validates authenticated extended card support" do
      card = base_card.merge(supportsAuthenticatedExtendedCard: true)
      expect(card).to be_valid_agent_card
    end

    it "validates JWS signatures" do
      signatures = [
        {
          keyId: "key-1",
          algorithm: "RS256",
          signature: "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."
        }
      ]
      
      card = base_card.merge(signatures: signatures)
      expect(card).to be_valid_agent_card
    end

    it "validates documentation and icon URLs" do
      card = base_card.merge(
        documentationUrl: "https://docs.example.com/agent",
        iconUrl: "https://example.com/icon.png"
      )
      expect(card).to be_valid_agent_card
    end

    it "validates metadata object" do
      metadata = {
        createdAt: "2024-01-01T00:00:00Z",
        updatedAt: Time.current.iso8601,
        version: "2.1.0",
        environment: "production",
        customField: "custom_value"
      }
      
      card = base_card.merge(metadata: metadata)
      expect(card).to be_valid_agent_card
    end
  end

  describe "Input/Output Modes Validation" do
    let(:base_card) { generate_minimal_agent_card }

    it "validates common MIME types" do
      common_modes = [
        "text/plain",
        "text/markdown",
        "application/json",
        "application/xml",
        "image/jpeg",
        "image/png",
        "application/pdf",
        "audio/mpeg",
        "video/mp4"
      ]
      
      card = base_card.merge(
        defaultInputModes: common_modes,
        defaultOutputModes: common_modes
      )
      expect(card).to be_valid_agent_card
    end

    it "validates wildcard MIME types" do
      wildcard_modes = [
        "text/*",
        "image/*",
        "audio/*",
        "video/*",
        "application/*"
      ]
      
      card = base_card.merge(
        defaultInputModes: wildcard_modes,
        defaultOutputModes: wildcard_modes
      )
      expect(card).to be_valid_agent_card
    end

    it "validates custom MIME types" do
      custom_modes = [
        "application/vnd.api+json",
        "application/vnd.example.custom+json",
        "text/vnd.example.special"
      ]
      
      card = base_card.merge(
        defaultInputModes: custom_modes,
        defaultOutputModes: custom_modes
      )
      expect(card).to be_valid_agent_card
    end
  end

  describe "Comprehensive Agent Card Validation" do
    it "validates the full agent card from fixture generator" do
      card = generate_full_agent_card
      
      # Validate overall structure
      expect(card).to be_valid_agent_card
      
      # Validate specific components
      expect(card[:skills]).to all(satisfy { |skill| 
        skill.key?(:id) && skill.key?(:name) && skill.key?(:description)
      })
      
      expect(card[:additionalInterfaces]).to all(satisfy { |interface|
        A2A::Types::VALID_TRANSPORTS.include?(interface[:transport])
      })
      
      expect(card[:securitySchemes]).to be_a(Hash)
      expect(card[:capabilities]).to be_a(Hash)
    end

    it "validates agent card serialization and deserialization" do
      original_card = generate_full_agent_card
      
      # Serialize to JSON and back
      json_string = original_card.to_json
      parsed_card = JSON.parse(json_string, symbolize_names: true)
      
      # Should still be valid after round-trip
      expect(parsed_card).to be_valid_agent_card
      
      # Key fields should be preserved
      expect(parsed_card[:name]).to eq(original_card[:name])
      expect(parsed_card[:version]).to eq(original_card[:version])
      expect(parsed_card[:preferredTransport]).to eq(original_card[:preferredTransport])
    end
  end

  describe "Edge Cases and Error Conditions" do
    let(:base_card) { generate_minimal_agent_card }

    it "handles empty arrays gracefully" do
      card = base_card.merge(
        skills: [],
        defaultInputModes: ["text/plain"], # Must have at least one
        defaultOutputModes: ["text/plain"]  # Must have at least one
      )
      expect(card).to be_valid_agent_card
    end

    it "handles very long field values" do
      long_description = "A" * 10000 # 10KB description
      card = base_card.merge(description: long_description)
      expect(card).to be_valid_agent_card
    end

    it "handles Unicode characters in all text fields" do
      unicode_card = base_card.merge(
        name: "测试代理 🤖",
        description: "Un agent de test avec des caractères spéciaux: éàü",
        skills: [
          {
            id: "unicode_skill",
            name: "Навык Unicode",
            description: "Обработка текста на разных языках 🌍"
          }
        ]
      )
      expect(unicode_card).to be_valid_agent_card
    end

    it "handles deeply nested security scheme structures" do
      complex_security = {
        "complexOAuth2" => {
          type: "oauth2",
          flows: {
            authorizationCode: {
              authorizationUrl: "https://auth.example.com/authorize",
              tokenUrl: "https://auth.example.com/token",
              refreshUrl: "https://auth.example.com/refresh",
              scopes: {
                "read:basic" => "Basic read access",
                "read:advanced" => "Advanced read access",
                "write:basic" => "Basic write access",
                "write:advanced" => "Advanced write access",
                "admin:full" => "Full administrative access"
              }
            }
          },
          extensions: {
            "x-token-introspection": "https://auth.example.com/introspect",
            "x-revocation-endpoint": "https://auth.example.com/revoke"
          }
        }
      }
      
      card = base_card.merge(securitySchemes: complex_security)
      expect(card).to be_valid_agent_card
    end
  end
end