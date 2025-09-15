# frozen_string_literal: true

require 'jwt'
require 'json'

module A2A
  module Client
    module Auth
      ##
      # JWT Bearer Token authentication strategy
      #
      # Supports both static JWT tokens and dynamic JWT generation
      # for authentication with A2A agents.
      #
      class JWT
        attr_reader :token, :algorithm, :secret, :payload, :headers

        ##
        # Initialize JWT authentication
        #
        # @param token [String, nil] Pre-generated JWT token
        # @param secret [String, nil] Secret key for JWT signing (required for dynamic tokens)
        # @param algorithm [String] JWT signing algorithm (default: 'HS256')
        # @param payload [Hash, nil] JWT payload for dynamic token generation
        # @param headers [Hash, nil] Additional JWT headers
        # @param expires_in [Integer, nil] Token expiration time in seconds
        def initialize(token: nil, secret: nil, algorithm: 'HS256', payload: nil, 
                       headers: nil, expires_in: nil)
          @token = token
          @secret = secret
          @algorithm = algorithm
          @payload = payload || {}
          @headers = headers || {}
          @expires_in = expires_in
          @generated_token = nil
          @token_expires_at = nil
          @token_mutex = Mutex.new

          validate_configuration!
        end

        ##
        # Get a valid JWT token
        #
        # @return [String] The JWT token
        def jwt_token
          if @token
            # Static token
            @token
          else
            # Dynamic token generation
            @token_mutex.synchronize do
              if token_expired?
                generate_token
              end
              @generated_token
            end
          end
        end

        ##
        # Get authorization header value
        #
        # @return [String] The authorization header value
        def authorization_header
          "Bearer #{jwt_token}"
        end

        ##
        # Apply authentication to a Faraday request
        #
        # @param request [Faraday::Request] The request to authenticate
        def apply_to_request(request)
          request.headers['Authorization'] = authorization_header
        end

        ##
        # Validate the JWT token
        #
        # @param token [String, nil] Token to validate (uses current token if nil)
        # @param verify_signature [Boolean] Whether to verify the signature
        # @return [Hash] Decoded JWT payload
        def validate_token(token = nil, verify_signature: true)
          token_to_validate = token || jwt_token
          
          if verify_signature && @secret
            ::JWT.decode(token_to_validate, @secret, true, { algorithm: @algorithm })
          else
            ::JWT.decode(token_to_validate, nil, false)
          end
        rescue ::JWT::DecodeError => e
          raise A2A::Errors::AuthenticationError.new("JWT validation failed: #{e.message}")
        end

        ##
        # Check if the token is expired
        #
        # @param token [String, nil] Token to check (uses current token if nil)
        # @return [Boolean] True if token is expired
        def token_expired?(token = nil)
          return false unless @expires_in || token

          if @generated_token && @token_expires_at
            # Check generated token expiration
            Time.now >= (@token_expires_at - 30) # 30 second buffer
          elsif token || @token
            # Check token payload expiration
            begin
              payload = validate_token(token, verify_signature: false).first
              exp = payload['exp']
              return false unless exp
              
              Time.now.to_i >= (exp - 30) # 30 second buffer
            rescue A2A::Errors::AuthenticationError
              true # Consider invalid tokens as expired
            end
          else
            false
          end
        end

        ##
        # Force regenerate the token (for dynamic tokens)
        #
        # @return [String] The new JWT token
        def regenerate_token!
          return @token if @token # Can't regenerate static tokens
          
          @token_mutex.synchronize do
            generate_token
          end
        end

        ##
        # Get token expiration time
        #
        # @return [Time, nil] Token expiration time
        def expires_at
          if @token_expires_at
            @token_expires_at
          elsif @token
            begin
              payload = validate_token(@token, verify_signature: false).first
              exp = payload['exp']
              Time.at(exp) if exp
            rescue A2A::Errors::AuthenticationError
              nil
            end
          else
            nil
          end
        end

        private

        ##
        # Validate the authentication configuration
        def validate_configuration!
          if @token.nil? && @secret.nil?
            raise ArgumentError, "Either token or secret must be provided"
          end

          if @token.nil? && @payload.empty?
            raise ArgumentError, "Payload is required for dynamic token generation"
          end

          unless ['HS256', 'HS384', 'HS512', 'RS256', 'RS384', 'RS512', 'ES256', 'ES384', 'ES512'].include?(@algorithm)
            raise ArgumentError, "Unsupported JWT algorithm: #{@algorithm}"
          end
        end

        ##
        # Generate a new JWT token
        #
        # @return [String] The generated JWT token
        def generate_token
          raise ArgumentError, "Cannot generate token without secret" unless @secret

          # Build payload with expiration
          token_payload = @payload.dup
          
          if @expires_in
            now = Time.now.to_i
            token_payload['iat'] = now
            token_payload['exp'] = now + @expires_in
            @token_expires_at = Time.now + @expires_in
          end

          # Generate token
          @generated_token = ::JWT.encode(token_payload, @secret, @algorithm, @headers)
        rescue ::JWT::EncodeError => e
          raise A2A::Errors::AuthenticationError.new("JWT generation failed: #{e.message}")
        end
      end
    end
  end
end