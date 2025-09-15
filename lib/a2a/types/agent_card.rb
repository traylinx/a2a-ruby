# frozen_string_literal: true

require "uri"

module A2A
  module Types
    ##
    # Represents an agent card in the A2A protocol
    #
    # Agent cards describe an agent's capabilities, interfaces, and metadata.
    # They are used for agent discovery and capability negotiation.
    #
    # @example Creating a basic agent card
    #   card = A2A::Types::AgentCard.new(
    #     name: "My Agent",
    #     description: "A helpful agent",
    #     version: "1.0.0",
    #     url: "https://example.com/agent",
    #     preferred_transport: "JSONRPC",
    #     skills: [skill],
    #     capabilities: capabilities,
    #     default_input_modes: ["text"],
    #     default_output_modes: ["text"]
    #   )
    #
    class AgentCard < A2A::Types::BaseModel
      attr_reader :name, :description, :version, :url, :preferred_transport,
                  :skills, :capabilities, :default_input_modes, :default_output_modes,
                  :additional_interfaces, :security, :security_schemes, :provider,
                  :protocol_version, :supports_authenticated_extended_card,
                  :signatures, :documentation_url, :icon_url

      ##
      # Initialize a new agent card
      #
      # @param name [String] Agent name (required)
      # @param description [String] Agent description (required)
      # @param version [String] Agent version (required)
      # @param url [String] Primary agent URL (required)
      # @param preferred_transport [String] Preferred transport protocol (required)
      # @param skills [Array<AgentSkill>] Agent skills (required)
      # @param capabilities [AgentCapabilities] Agent capabilities (required)
      # @param default_input_modes [Array<String>] Default input modes (required)
      # @param default_output_modes [Array<String>] Default output modes (required)
      # @param additional_interfaces [Array<AgentInterface>, nil] Additional interfaces
      # @param security [Array<String>, nil] Security requirements
      # @param security_schemes [Hash<String, SecurityScheme>, nil] Security scheme definitions
      # @param provider [String, nil] Provider information
      # @param protocol_version [String, nil] A2A protocol version
      # @param supports_authenticated_extended_card [Boolean, nil] Extended card support
      # @param signatures [Array<AgentCardSignature>, nil] JWS signatures
      # @param documentation_url [String, nil] Documentation URL
      # @param icon_url [String, nil] Icon URL
      def initialize(name:, description:, version:, url:, preferred_transport:, skills:,
                     capabilities:, default_input_modes:, default_output_modes:,
                     additional_interfaces: nil, security: nil, security_schemes: nil,
                     provider: nil, protocol_version: nil, supports_authenticated_extended_card: nil,
                     signatures: nil, documentation_url: nil, icon_url: nil)
        @name = name
        @description = description
        @version = version
        @url = url
        @preferred_transport = preferred_transport
        @skills = skills.map { |s| s.is_a?(AgentSkill) ? s : AgentSkill.from_h(s) }
        @capabilities = capabilities.is_a?(AgentCapabilities) ? capabilities : AgentCapabilities.from_h(capabilities)
        @default_input_modes = default_input_modes
        @default_output_modes = default_output_modes
        @additional_interfaces = additional_interfaces&.map do |i|
          i.is_a?(AgentInterface) ? i : AgentInterface.from_h(i)
        end
        @security = security
        @security_schemes = process_security_schemes(security_schemes)
        @provider = provider
        @protocol_version = protocol_version || "1.0"
        @supports_authenticated_extended_card = supports_authenticated_extended_card
        @signatures = signatures&.map { |s| s.is_a?(AgentCardSignature) ? s : AgentCardSignature.from_h(s) }
        @documentation_url = documentation_url
        @icon_url = icon_url

        validate!
      end

      ##
      # Get all available interfaces (primary + additional)
      #
      # @return [Array<AgentInterface>] All interfaces
      def all_interfaces
        interfaces = [AgentInterface.new(transport: @preferred_transport, url: @url)]
        interfaces.concat(@additional_interfaces) if @additional_interfaces
        interfaces
      end

      ##
      # Check if the agent supports a specific transport
      #
      # @param transport [String] The transport to check
      # @return [Boolean] True if supported
      def supports_transport?(transport)
        all_interfaces.any? { |i| i.transport == transport }
      end

      ##
      # Get the URL for a specific transport
      #
      # @param transport [String] The transport to get URL for
      # @return [String, nil] The URL or nil if not supported
      def url_for_transport(transport)
        interface = all_interfaces.find { |i| i.transport == transport }
        interface&.url
      end

      private

      ##
      # Process security schemes hash into SecurityScheme objects
      #
      # @param schemes [Hash, nil] Security schemes hash
      # @return [Hash<String, SecurityScheme>, nil] Processed security schemes
      def process_security_schemes(schemes)
        return nil if schemes.nil?
        return schemes if schemes.is_a?(Hash) && schemes.values.all?(SecurityScheme)

        processed = {}
        schemes.each do |name, scheme_data|
          processed[name.to_s] = if scheme_data.is_a?(SecurityScheme)
                                   scheme_data
                                 else
                                   SecurityScheme.from_h(scheme_data)
                                 end
        end
        processed
      end

      def validate!
        validate_required(:name, :description, :version, :url, :preferred_transport,
                          :skills, :capabilities, :default_input_modes, :default_output_modes)
        validate_inclusion(:preferred_transport, VALID_TRANSPORTS)
        validate_array_type(:skills, AgentSkill)
        validate_type(:capabilities, AgentCapabilities)
        validate_array_type(:additional_interfaces, AgentInterface) if @additional_interfaces
        validate_array_type(:signatures, AgentCardSignature) if @signatures
        validate_array_type(:default_input_modes, String)
        validate_array_type(:default_output_modes, String)
        validate_array_type(:security, String) if @security
        validate_security_schemes if @security_schemes
        if @supports_authenticated_extended_card
          validate_type(:supports_authenticated_extended_card,
                        [TrueClass, FalseClass])
        end
        validate_url_format(:url)
        validate_url_format(:documentation_url) if @documentation_url
        validate_url_format(:icon_url) if @icon_url
      end

      ##
      # Validate security schemes
      def validate_security_schemes
        validate_type(:security_schemes, Hash)
        @security_schemes.each do |name, scheme|
          raise ArgumentError, "security_schemes[#{name}] must be a SecurityScheme" unless scheme.is_a?(SecurityScheme)
        end
      end

      ##
      # Validate URL format
      #
      # @param field [Symbol] The field name containing the URL
      def validate_url_format(field)
        value = instance_variable_get("@#{field}")
        return if value.nil?

        validate_type(field, String)

        begin
          uri = URI.parse(value)
          raise ArgumentError, "#{field} must be a valid HTTP or HTTPS URL" unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
        rescue URI::InvalidURIError
          raise ArgumentError, "#{field} must be a valid URL"
        end
      end
    end

    ##
    # Represents an agent skill
    #
    # Skills define specific capabilities that an agent can perform,
    # including supported input/output modes and security requirements.
    #
    # @example Creating a skill
    #   skill = A2A::Types::AgentSkill.new(
    #     id: "text_analysis",
    #     name: "Text Analysis",
    #     description: "Analyze and process text content",
    #     tags: ["nlp", "analysis"],
    #     examples: [
    #       {
    #         input: "Analyze this text",
    #         output: "Analysis results..."
    #       }
    #     ],
    #     input_modes: ["text"],
    #     output_modes: ["text", "data"],
    #     security: ["api_key"]
    #   )
    #
    class AgentSkill < A2A::Types::BaseModel
      attr_reader :id, :name, :description, :tags, :examples, :input_modes, :output_modes, :security

      ##
      # Initialize a new agent skill
      #
      # @param id [String] Skill identifier (required)
      # @param name [String] Skill name (required)
      # @param description [String] Skill description (required)
      # @param tags [Array<String>, nil] Skill tags for categorization
      # @param examples [Array<Hash>, nil] Usage examples with input/output
      # @param input_modes [Array<String>, nil] Supported input modes (text, file, data)
      # @param output_modes [Array<String>, nil] Supported output modes (text, file, data)
      # @param security [Array<String>, nil] Security requirements for this skill
      def initialize(id:, name:, description:, tags: nil, examples: nil,
                     input_modes: nil, output_modes: nil, security: nil)
        @id = id
        @name = name
        @description = description
        @tags = tags
        @examples = examples
        @input_modes = input_modes
        @output_modes = output_modes
        @security = security

        validate!
      end

      ##
      # Check if the skill supports a specific input mode
      #
      # @param mode [String] The input mode to check
      # @return [Boolean] True if supported
      def supports_input_mode?(mode)
        return true if @input_modes.nil? # nil means all modes supported

        @input_modes.include?(mode)
      end

      ##
      # Check if the skill supports a specific output mode
      #
      # @param mode [String] The output mode to check
      # @return [Boolean] True if supported
      def supports_output_mode?(mode)
        return true if @output_modes.nil? # nil means all modes supported

        @output_modes.include?(mode)
      end

      ##
      # Check if the skill has a specific security requirement
      #
      # @param requirement [String] The security requirement to check
      # @return [Boolean] True if required
      def requires_security?(requirement)
        return false if @security.nil?

        @security.include?(requirement)
      end

      private

      def validate!
        validate_required(:id, :name, :description)
        validate_type(:id, String)
        validate_type(:name, String)
        validate_type(:description, String)
        validate_array_type(:tags, String) if @tags
        validate_array_type(:input_modes, String) if @input_modes
        validate_array_type(:output_modes, String) if @output_modes
        validate_array_type(:security, String) if @security
        validate_examples if @examples
      end

      ##
      # Validate examples structure
      def validate_examples
        validate_type(:examples, Array)
        @examples.each_with_index do |example, index|
          raise ArgumentError, "examples[#{index}] must be a Hash" unless example.is_a?(Hash)

          # Examples should have at least input or description
          unless example.key?(:input) || example.key?("input") ||
                 example.key?(:description) || example.key?("description")
            raise ArgumentError, "examples[#{index}] must have input or description"
          end
        end
      end
    end

    ##
    # Represents agent capabilities
    #
    # Capabilities define what features and protocols the agent supports,
    # such as streaming, push notifications, and extensions.
    #
    # @example Creating capabilities
    #   capabilities = A2A::Types::AgentCapabilities.new(
    #     streaming: true,
    #     push_notifications: true,
    #     state_transition_history: false,
    #     extensions: ["custom-extension-1"]
    #   )
    #
    class AgentCapabilities < A2A::Types::BaseModel
      attr_reader :streaming, :push_notifications, :state_transition_history, :extensions

      ##
      # Initialize new agent capabilities
      #
      # @param streaming [Boolean, nil] Whether the agent supports streaming responses
      # @param push_notifications [Boolean, nil] Whether the agent supports push notifications
      # @param state_transition_history [Boolean, nil] Whether the agent maintains state history
      # @param extensions [Array<String>, nil] List of supported extension URIs
      def initialize(streaming: nil, push_notifications: nil, state_transition_history: nil, extensions: nil)
        @streaming = streaming
        @push_notifications = push_notifications
        @state_transition_history = state_transition_history
        @extensions = extensions

        validate!
      end

      ##
      # Check if streaming is supported
      #
      # @return [Boolean] True if streaming is supported
      def streaming?
        @streaming == true
      end

      ##
      # Check if push notifications are supported
      #
      # @return [Boolean] True if push notifications are supported
      def push_notifications?
        @push_notifications == true
      end

      ##
      # Check if state transition history is supported
      #
      # @return [Boolean] True if state history is supported
      def state_transition_history?
        @state_transition_history == true
      end

      ##
      # Check if a specific extension is supported
      #
      # @param extension_uri [String] The extension URI to check
      # @return [Boolean] True if the extension is supported
      def supports_extension?(extension_uri)
        return false if @extensions.nil?

        @extensions.include?(extension_uri)
      end

      private

      def validate!
        validate_type(:streaming, [TrueClass, FalseClass]) if @streaming
        validate_type(:push_notifications, [TrueClass, FalseClass]) if @push_notifications
        validate_type(:state_transition_history, [TrueClass, FalseClass]) if @state_transition_history
        validate_array_type(:extensions, String) if @extensions
      end
    end

    ##
    # Represents an agent interface
    #
    # Interfaces define the transport protocols and URLs that can be used
    # to communicate with the agent.
    #
    # @example Creating an interface
    #   interface = A2A::Types::AgentInterface.new(
    #     transport: "JSONRPC",
    #     url: "https://example.com/agent/rpc"
    #   )
    #
    class AgentInterface < A2A::Types::BaseModel
      attr_reader :transport, :url

      ##
      # Initialize a new agent interface
      #
      # @param transport [String] Transport protocol (JSONRPC, GRPC, HTTP+JSON)
      # @param url [String] Interface URL
      def initialize(transport:, url:)
        @transport = transport
        @url = url
        validate!
      end

      ##
      # Check if this interface uses the specified transport
      #
      # @param transport_type [String] The transport type to check
      # @return [Boolean] True if this interface uses the transport
      def uses_transport?(transport_type)
        @transport == transport_type
      end

      ##
      # Check if this is a secure interface (HTTPS)
      #
      # @return [Boolean] True if the URL uses HTTPS
      def secure?
        @url.start_with?("https://")
      end

      private

      def validate!
        validate_required(:transport, :url)
        validate_inclusion(:transport, VALID_TRANSPORTS)
        validate_type(:url, String)
        validate_url_format
      end

      ##
      # Validate URL format
      def validate_url_format
        uri = URI.parse(@url)
        raise ArgumentError, "url must be a valid HTTP or HTTPS URL" unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      rescue URI::InvalidURIError
        raise ArgumentError, "url must be a valid URL"
      end
    end

    ##
    # Represents an agent card signature
    #
    # Signatures provide cryptographic verification of agent cards using
    # JSON Web Signature (JWS) format.
    #
    # @example Creating a signature
    #   signature = A2A::Types::AgentCardSignature.new(
    #     signature: "eyJhbGciOiJSUzI1NiJ9...",
    #     protected_header: "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9"
    #   )
    #
    class AgentCardSignature < A2A::Types::BaseModel
      attr_reader :signature, :protected_header

      ##
      # Initialize a new agent card signature
      #
      # @param signature [String] JWS signature value (base64url encoded)
      # @param protected_header [String] JWS protected header (base64url encoded JSON)
      def initialize(signature:, protected_header:)
        @signature = signature
        @protected_header = protected_header
        validate!
      end

      ##
      # Decode the protected header
      #
      # @return [Hash] The decoded header as a hash
      def decoded_header
        require "base64"
        require "json"

        # Add padding if needed for base64url decoding
        padded = @protected_header
        case padded.length % 4
        when 2
          padded += "=="
        when 3
          padded += "="
        end

        decoded = Base64.urlsafe_decode64(padded)
        JSON.parse(decoded)
      rescue StandardError => e
        raise ArgumentError, "Invalid protected header: #{e.message}"
      end

      ##
      # Get the algorithm from the protected header
      #
      # @return [String, nil] The algorithm or nil if not present
      def algorithm
        decoded_header["alg"]
      rescue StandardError
        nil
      end

      ##
      # Check if the signature uses a specific algorithm
      #
      # @param alg [String] The algorithm to check
      # @return [Boolean] True if the signature uses the algorithm
      def uses_algorithm?(alg)
        algorithm == alg
      end

      private

      def validate!
        validate_required(:signature, :protected_header)
        validate_type(:signature, String)
        validate_type(:protected_header, String)
        validate_base64url_format(:signature)
        validate_base64url_format(:protected_header)
        validate_protected_header_content
      end

      ##
      # Validate base64url format
      #
      # @param field [Symbol] The field name
      def validate_base64url_format(field)
        value = instance_variable_get("@#{field}")
        return if value.match?(/\A[A-Za-z0-9_-]+\z/)

        raise ArgumentError, "#{field} must be valid base64url encoded"
      end

      ##
      # Validate protected header content
      def validate_protected_header_content
        header = decoded_header
        unless header.is_a?(Hash) && header["alg"]
          raise ArgumentError,
                "protected_header must contain a valid algorithm"
        end
      rescue StandardError => e
        raise ArgumentError, "protected_header must be valid base64url encoded JSON: #{e.message}"
      end
    end
  end
end
