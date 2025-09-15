# frozen_string_literal: true

module A2A
  module Types
    ##
    # Base class for security schemes (discriminated union)
    #
    # Security schemes define how authentication and authorization
    # should be handled for agent interactions.
    #
    class SecurityScheme < BaseModel
      attr_reader :type

      ##
      # Create a security scheme from a hash (factory method)
      #
      # @param hash [Hash] The hash representation
      # @return [SecurityScheme] The appropriate security scheme subclass instance
      def self.from_h(hash)
        return nil if hash.nil?
        
        type = hash[:type] || hash['type']
        case type
        when SECURITY_TYPE_API_KEY
          ApiKeySecurityScheme.from_h(hash)
        when SECURITY_TYPE_HTTP
          HttpSecurityScheme.from_h(hash)
        when SECURITY_TYPE_OAUTH2
          OAuth2SecurityScheme.from_h(hash)
        when SECURITY_TYPE_OPENID_CONNECT
          OpenIdConnectSecurityScheme.from_h(hash)
        when SECURITY_TYPE_MUTUAL_TLS
          MutualTlsSecurityScheme.from_h(hash)
        else
          raise ArgumentError, "Unknown security scheme type: #{type}"
        end
      end

      protected

      def initialize(type:)
        @type = type
        validate!
      end

      private

      def validate!
        validate_required(:type)
        validate_inclusion(:type, VALID_SECURITY_TYPES)
      end
    end

    ##
    # API Key security scheme
    #
    class ApiKeySecurityScheme < SecurityScheme
      attr_reader :name, :location

      ##
      # Initialize a new API key security scheme
      #
      # @param name [String] The name of the API key parameter
      # @param location [String] Where the API key is sent ("query", "header", "cookie")
      def initialize(name:, location:)
        @name = name
        @location = location
        super(type: SECURITY_TYPE_API_KEY)
      end

      private

      def validate!
        super
        validate_required(:name, :location)
        validate_inclusion(:location, %w[query header cookie])
      end
    end

    ##
    # HTTP security scheme (Basic, Bearer, etc.)
    #
    class HttpSecurityScheme < SecurityScheme
      attr_reader :scheme, :bearer_format

      ##
      # Initialize a new HTTP security scheme
      #
      # @param scheme [String] The HTTP authentication scheme ("basic", "bearer", etc.)
      # @param bearer_format [String, nil] Format of bearer token (e.g., "JWT")
      def initialize(scheme:, bearer_format: nil)
        @scheme = scheme
        @bearer_format = bearer_format
        super(type: SECURITY_TYPE_HTTP)
      end

      private

      def validate!
        super
        validate_required(:scheme)
        validate_inclusion(:scheme, %w[basic bearer digest])
      end
    end

    ##
    # OAuth 2.0 security scheme
    #
    class OAuth2SecurityScheme < SecurityScheme
      attr_reader :flows, :scopes

      ##
      # Initialize a new OAuth 2.0 security scheme
      #
      # @param flows [Hash] OAuth 2.0 flows configuration
      # @param scopes [Hash, nil] Available scopes
      def initialize(flows:, scopes: nil)
        @flows = flows
        @scopes = scopes
        super(type: SECURITY_TYPE_OAUTH2)
      end

      private

      def validate!
        super
        validate_required(:flows)
        validate_type(:flows, Hash)
      end
    end

    ##
    # OpenID Connect security scheme
    #
    class OpenIdConnectSecurityScheme < SecurityScheme
      attr_reader :open_id_connect_url

      ##
      # Initialize a new OpenID Connect security scheme
      #
      # @param open_id_connect_url [String] The OpenID Connect discovery URL
      def initialize(open_id_connect_url:)
        @open_id_connect_url = open_id_connect_url
        super(type: SECURITY_TYPE_OPENID_CONNECT)
      end

      private

      def validate!
        super
        validate_required(:open_id_connect_url)
        validate_type(:open_id_connect_url, String)
      end
    end

    ##
    # Mutual TLS security scheme
    #
    class MutualTlsSecurityScheme < SecurityScheme
      ##
      # Initialize a new mutual TLS security scheme
      def initialize
        super(type: SECURITY_TYPE_MUTUAL_TLS)
      end
    end
  end
end