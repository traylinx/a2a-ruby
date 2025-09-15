# frozen_string_literal: true

require 'time'
require 'json'

module A2A
  module Protocol
    ##
    # Serves agent cards with caching and automatic generation
    #
    # The agent card server provides HTTP endpoints for agent card discovery,
    # supports multiple output formats, and includes configurable caching.
    #
    # @example Basic usage
    #   server = A2A::Protocol::AgentCardServer.new
    #   server.configure do |config|
    #     config.cache_ttl = 300 # 5 minutes
    #     config.enable_signatures = true
    #   end
    #   
    #   # Register capabilities
    #   server.capability_registry.register(capability)
    #   
    #   # Generate agent card
    #   card = server.generate_card(
    #     name: "My Agent",
    #     description: "A helpful agent"
    #   )
    #
    class AgentCardServer
      attr_reader :capability_registry, :config

      ##
      # Configuration for the agent card server
      #
      class Config
        attr_accessor :cache_ttl, :enable_signatures, :signing_key, :signing_algorithm,
                      :default_protocol_version, :enable_authenticated_extended_cards,
                      :card_modification_callback

        def initialize
          @cache_ttl = 300 # 5 minutes
          @enable_signatures = false
          @signing_key = nil
          @signing_algorithm = 'RS256'
          @default_protocol_version = '1.0'
          @enable_authenticated_extended_cards = false
          @card_modification_callback = nil
        end
      end

      ##
      # Initialize a new agent card server
      #
      # @param capability_registry [CapabilityRegistry, nil] Optional registry
      def initialize(capability_registry: nil)
        @capability_registry = capability_registry || CapabilityRegistry.new
        @config = Config.new
        @cache = {}
        @cache_timestamps = {}
      end

      ##
      # Configure the server
      #
      # @yield [config] Configuration block
      # @yieldparam config [Config] The configuration object
      def configure
        yield(@config) if block_given?
      end

      ##
      # Generate an agent card from registered capabilities
      #
      # @param name [String] Agent name
      # @param description [String] Agent description
      # @param version [String] Agent version
      # @param url [String] Primary agent URL
      # @param preferred_transport [String] Preferred transport
      # @param additional_options [Hash] Additional card options
      # @return [A2A::Types::AgentCard] The generated agent card
      def generate_card(name:, description:, version: '1.0.0', url:, 
                       preferred_transport: 'JSONRPC', **additional_options)
        
        # Convert capabilities to skills
        skills = @capability_registry.all.map { |cap| capability_to_skill(cap) }
        
        # Determine capabilities from registry
        capabilities = determine_capabilities
        
        # Build default input/output modes from skills
        input_modes = determine_input_modes(skills)
        output_modes = determine_output_modes(skills)
        
        # Create the agent card
        card_options = {
          name: name,
          description: description,
          version: version,
          url: url,
          preferred_transport: preferred_transport,
          skills: skills,
          capabilities: capabilities,
          default_input_modes: input_modes,
          default_output_modes: output_modes,
          protocol_version: @config.default_protocol_version,
          supports_authenticated_extended_card: @config.enable_authenticated_extended_cards
        }.merge(additional_options)
        
        card = A2A::Types::AgentCard.new(**card_options)
        
        # Add signatures if enabled
        if @config.enable_signatures && @config.signing_key
          signatures = [generate_signature(card)]
          card = A2A::Types::AgentCard.new(**card_options.merge(signatures: signatures))
        end
        
        card
      end

      ##
      # Get agent card with caching
      #
      # @param cache_key [String] Cache key for the card
      # @param card_params [Hash] Parameters for card generation
      # @return [A2A::Types::AgentCard] The agent card
      def get_card(cache_key: 'default', **card_params)
        # Check cache
        if cached_card = get_from_cache(cache_key)
          return cached_card
        end
        
        # Generate new card
        card = generate_card(**card_params)
        
        # Cache the card
        store_in_cache(cache_key, card)
        
        card
      end

      ##
      # Get authenticated extended agent card
      #
      # This method allows for dynamic modification of the agent card
      # based on the authentication context.
      #
      # @param auth_context [Hash] Authentication context
      # @param base_card_params [Hash] Base card parameters
      # @return [A2A::Types::AgentCard] The extended agent card
      def get_authenticated_extended_card(auth_context: {}, **base_card_params)
        unless @config.enable_authenticated_extended_cards
          raise A2A::Errors::A2AError.new(
            "Authenticated extended cards are not enabled",
            code: -32001
          )
        end
        
        # Generate base card
        card = generate_card(**base_card_params)
        
        # Apply modifications based on auth context
        if @config.card_modification_callback
          card = @config.card_modification_callback.call(card, auth_context)
        end
        
        card
      end

      ##
      # Serve agent card as HTTP response data
      #
      # @param format [String] Output format ('json' or 'jws')
      # @param cache_key [String] Cache key
      # @param card_params [Hash] Card generation parameters
      # @return [Hash] HTTP response data with headers and body
      def serve_card(format: 'json', cache_key: 'default', **card_params)
        card = get_card(cache_key: cache_key, **card_params)
        
        case format.downcase
        when 'json'
          {
            status: 200,
            headers: {
              'Content-Type' => 'application/json',
              'Cache-Control' => "max-age=#{@config.cache_ttl}"
            },
            body: card.to_json
          }
        when 'jws'
          if @config.enable_signatures && @config.signing_key
            jws_token = generate_jws_token(card)
            {
              status: 200,
              headers: {
                'Content-Type' => 'application/jose+json',
                'Cache-Control' => "max-age=#{@config.cache_ttl}"
              },
              body: jws_token
            }
          else
            {
              status: 400,
              headers: { 'Content-Type' => 'application/json' },
              body: { error: 'JWS signing not configured' }.to_json
            }
          end
        else
          {
            status: 400,
            headers: { 'Content-Type' => 'application/json' },
            body: { error: "Unsupported format: #{format}" }.to_json
          }
        end
      end

      ##
      # Clear cache
      #
      # @param cache_key [String, nil] Specific key to clear, or nil for all
      def clear_cache(cache_key = nil)
        if cache_key
          @cache.delete(cache_key)
          @cache_timestamps.delete(cache_key)
        else
          @cache.clear
          @cache_timestamps.clear
        end
      end

      ##
      # Get cache statistics
      #
      # @return [Hash] Cache statistics
      def cache_stats
        {
          entries: @cache.size,
          keys: @cache.keys,
          oldest_entry: @cache_timestamps.values.min,
          newest_entry: @cache_timestamps.values.max
        }
      end

      private

      ##
      # Convert a capability to an agent skill
      #
      # @param capability [Capability] The capability to convert
      # @return [A2A::Types::AgentSkill] The converted skill
      def capability_to_skill(capability)
        A2A::Types::AgentSkill.new(
          id: capability.name,
          name: capability.name.split('_').map(&:capitalize).join(' '),
          description: capability.description,
          tags: capability.tags,
          examples: capability.examples,
          input_modes: determine_capability_input_modes(capability),
          output_modes: determine_capability_output_modes(capability),
          security: capability.security_requirements
        )
      end

      ##
      # Determine agent capabilities from registry
      #
      # @return [A2A::Types::AgentCapabilities] The agent capabilities
      def determine_capabilities
        streaming = @capability_registry.all.any?(&:streaming?)
        push_notifications = false # TODO: Determine from server config
        state_history = false # TODO: Determine from server config
        extensions = [] # TODO: Collect from capabilities
        
        A2A::Types::AgentCapabilities.new(
          streaming: streaming,
          push_notifications: push_notifications,
          state_transition_history: state_history,
          extensions: extensions
        )
      end

      ##
      # Determine input modes from skills
      #
      # @param skills [Array<A2A::Types::AgentSkill>] The skills
      # @return [Array<String>] Input modes
      def determine_input_modes(skills)
        modes = skills.flat_map { |skill| skill.input_modes || ['text'] }.uniq
        modes.empty? ? ['text'] : modes
      end

      ##
      # Determine output modes from skills
      #
      # @param skills [Array<A2A::Types::AgentSkill>] The skills
      # @return [Array<String>] Output modes
      def determine_output_modes(skills)
        modes = skills.flat_map { |skill| skill.output_modes || ['text'] }.uniq
        modes.empty? ? ['text'] : modes
      end

      ##
      # Determine input modes for a capability
      #
      # @param capability [Capability] The capability
      # @return [Array<String>] Input modes
      def determine_capability_input_modes(capability)
        # Analyze input schema to determine modes
        return ['text'] unless capability.input_schema
        
        modes = ['text'] # Default to text
        
        # Check if schema accepts file inputs
        if schema_accepts_files?(capability.input_schema)
          modes << 'file'
        end
        
        # Check if schema accepts structured data
        if schema_accepts_data?(capability.input_schema)
          modes << 'data'
        end
        
        modes.uniq
      end

      ##
      # Determine output modes for a capability
      #
      # @param capability [Capability] The capability
      # @return [Array<String>] Output modes
      def determine_capability_output_modes(capability)
        # Analyze output schema to determine modes
        return ['text'] unless capability.output_schema
        
        modes = ['text'] # Default to text
        
        # Check if schema produces files
        if schema_produces_files?(capability.output_schema)
          modes << 'file'
        end
        
        # Check if schema produces structured data
        if schema_produces_data?(capability.output_schema)
          modes << 'data'
        end
        
        modes.uniq
      end

      ##
      # Check if schema accepts file inputs
      #
      # @param schema [Hash] The JSON schema
      # @return [Boolean] True if files are accepted
      def schema_accepts_files?(schema)
        # Simple heuristic: look for file-related properties
        return false unless schema.is_a?(Hash)
        
        properties = schema[:properties] || schema['properties'] || {}
        properties.any? do |name, prop_schema|
          name.to_s.include?('file') || 
          (prop_schema.is_a?(Hash) && prop_schema[:format] == 'binary')
        end
      end

      ##
      # Check if schema accepts structured data
      #
      # @param schema [Hash] The JSON schema
      # @return [Boolean] True if structured data is accepted
      def schema_accepts_data?(schema)
        return false unless schema.is_a?(Hash)
        
        type = schema[:type] || schema['type']
        type == 'object' || type == 'array'
      end

      ##
      # Check if schema produces files
      #
      # @param schema [Hash] The JSON schema
      # @return [Boolean] True if files are produced
      def schema_produces_files?(schema)
        schema_accepts_files?(schema) # Same logic for now
      end

      ##
      # Check if schema produces structured data
      #
      # @param schema [Hash] The JSON schema
      # @return [Boolean] True if structured data is produced
      def schema_produces_data?(schema)
        schema_accepts_data?(schema) # Same logic for now
      end

      ##
      # Get card from cache if valid
      #
      # @param cache_key [String] The cache key
      # @return [A2A::Types::AgentCard, nil] Cached card or nil
      def get_from_cache(cache_key)
        return nil unless @cache.key?(cache_key)
        
        timestamp = @cache_timestamps[cache_key]
        return nil unless timestamp
        
        # Check if cache entry is still valid
        if Time.now - timestamp < @config.cache_ttl
          @cache[cache_key]
        else
          # Remove expired entry
          @cache.delete(cache_key)
          @cache_timestamps.delete(cache_key)
          nil
        end
      end

      ##
      # Store card in cache
      #
      # @param cache_key [String] The cache key
      # @param card [A2A::Types::AgentCard] The card to cache
      def store_in_cache(cache_key, card)
        @cache[cache_key] = card
        @cache_timestamps[cache_key] = Time.now
      end

      ##
      # Generate a JWS signature for the agent card
      #
      # @param card [A2A::Types::AgentCard] The card to sign
      # @return [A2A::Types::AgentCardSignature] The signature
      def generate_signature(card)
        # This is a placeholder implementation
        # In a real implementation, you would use a proper JWT library
        
        header = {
          alg: @config.signing_algorithm,
          typ: 'JWT'
        }
        
        require 'base64'
        header_b64 = Base64.urlsafe_encode64(header.to_json).gsub('=', '')
        
        # Placeholder signature (in real implementation, sign with private key)
        signature_b64 = Base64.urlsafe_encode64("signature_#{Time.now.to_i}").gsub('=', '')
        
        A2A::Types::AgentCardSignature.new(
          signature: signature_b64,
          protected_header: header_b64
        )
      end

      ##
      # Generate a complete JWS token for the agent card
      #
      # @param card [A2A::Types::AgentCard] The card to sign
      # @return [String] The JWS token
      def generate_jws_token(card)
        # This is a placeholder implementation
        # In a real implementation, you would use a proper JWT library
        
        header = {
          alg: @config.signing_algorithm,
          typ: 'JWT'
        }
        
        payload = card.to_h
        
        require 'base64'
        header_b64 = Base64.urlsafe_encode64(header.to_json).gsub('=', '')
        payload_b64 = Base64.urlsafe_encode64(payload.to_json).gsub('=', '')
        
        # Placeholder signature (in real implementation, sign with private key)
        signature_b64 = Base64.urlsafe_encode64("signature_#{Time.now.to_i}").gsub('=', '')
        
        "#{header_b64}.#{payload_b64}.#{signature_b64}"
      end
    end

    ##
    # HTTP endpoint handlers for agent card serving
    #
    # Provides Rack-compatible handlers for serving agent cards
    # over HTTP with proper content negotiation and caching.
    #
    class AgentCardEndpoints
      def initialize(server)
        @server = server
      end

      ##
      # Handle agent card requests
      #
      # @param env [Hash] Rack environment
      # @return [Array] Rack response [status, headers, body]
      def call(env)
        request = Rack::Request.new(env) if defined?(Rack::Request)
        
        # Simple request parsing for non-Rack environments
        method = env['REQUEST_METHOD'] || 'GET'
        path = env['PATH_INFO'] || env['REQUEST_URI'] || '/'
        query_params = parse_query_string(env['QUERY_STRING'] || '')
        
        case path
        when '/agent-card', '/agent-card.json'
          handle_agent_card_request(method, query_params)
        when '/agent-card.jws'
          handle_agent_card_jws_request(method, query_params)
        when '/capabilities'
          handle_capabilities_request(method, query_params)
        else
          [404, { 'Content-Type' => 'application/json' }, ['{"error":"Not found"}']]
        end
      end

      private

      ##
      # Handle agent card JSON requests
      def handle_agent_card_request(method, params)
        return method_not_allowed unless method == 'GET'
        
        response = @server.serve_card(
          format: 'json',
          cache_key: params['cache_key'] || 'default',
          name: params['name'] || 'Agent',
          description: params['description'] || 'An A2A agent',
          version: params['version'] || '1.0.0',
          url: params['url'] || 'https://example.com/agent'
        )
        
        [response[:status], response[:headers], [response[:body]]]
      end

      ##
      # Handle agent card JWS requests
      def handle_agent_card_jws_request(method, params)
        return method_not_allowed unless method == 'GET'
        
        response = @server.serve_card(
          format: 'jws',
          cache_key: params['cache_key'] || 'default',
          name: params['name'] || 'Agent',
          description: params['description'] || 'An A2A agent',
          version: params['version'] || '1.0.0',
          url: params['url'] || 'https://example.com/agent'
        )
        
        [response[:status], response[:headers], [response[:body]]]
      end

      ##
      # Handle capabilities listing requests
      def handle_capabilities_request(method, params)
        return method_not_allowed unless method == 'GET'
        
        capabilities = @server.capability_registry.to_h
        
        [
          200,
          { 'Content-Type' => 'application/json' },
          [capabilities.to_json]
        ]
      end

      ##
      # Parse query string into hash
      def parse_query_string(query_string)
        return {} if query_string.empty?
        
        params = {}
        query_string.split('&').each do |pair|
          key, value = pair.split('=', 2)
          next unless key
          
          key = URI.decode_www_form_component(key) if defined?(URI.decode_www_form_component)
          value = URI.decode_www_form_component(value || '') if defined?(URI.decode_www_form_component)
          params[key] = value
        end
        params
      end

      ##
      # Return method not allowed response
      def method_not_allowed
        [
          405,
          { 'Content-Type' => 'application/json' },
          ['{"error":"Method not allowed"}']
        ]
      end
    end
  end
end