# frozen_string_literal: true

require 'base64'
require_relative '../../errors'

module A2A
  module Server
    module Middleware
      ##
      # Authentication middleware for A2A requests
      #
      # Handles authentication for A2A requests based on various security schemes
      # including OAuth2, JWT, API keys, and HTTP authentication.
      #
      # @example Basic usage
      #   middleware = AuthenticationMiddleware.new(
      #     schemes: ['bearer', 'api_key'],
      #     required: true
      #   )
      #
      class AuthenticationMiddleware
        attr_reader :schemes, :required, :authenticators

        ##
        # Initialize authentication middleware
        #
        # @param schemes [Array<String>] Allowed authentication schemes
        # @param required [Boolean] Whether authentication is required
        # @param authenticators [Hash] Custom authenticator implementations
        def initialize(schemes: [], required: false, authenticators: {})
          @schemes = schemes.map(&:to_s)
          @required = required
          @authenticators = default_authenticators.merge(authenticators)
        end

        ##
        # Process authentication for a request
        #
        # @param request [A2A::Protocol::Request] The JSON-RPC request
        # @param context [A2A::Server::Context] The request context
        # @yield Block to continue the middleware chain
        # @return [Object] The result from the next middleware or handler
        def call(request, context)
          # Extract authentication information
          auth_info = extract_authentication(request, context)
          
          if auth_info
            scheme, credentials = auth_info
            
            # Check if scheme is allowed
            if @schemes.empty? || @schemes.include?(scheme)
              # Authenticate using the appropriate authenticator
              authenticate(scheme, credentials, context)
            else
              raise A2A::Errors::AuthorizationFailed.new(
                "Authentication scheme '#{scheme}' not supported"
              )
            end
          elsif @required
            raise A2A::Errors::AuthenticationRequired.new(
              "Authentication required. Supported schemes: #{@schemes.join(', ')}"
            )
          end
          
          # Continue to next middleware
          yield
        end

        ##
        # Add a custom authenticator
        #
        # @param scheme [String] The authentication scheme name
        # @param authenticator [Proc] The authenticator proc
        def add_authenticator(scheme, authenticator)
          @authenticators[scheme.to_s] = authenticator
        end

        private

        ##
        # Extract authentication information from request/context
        #
        # @param request [A2A::Protocol::Request] The request
        # @param context [A2A::Server::Context] The context
        # @return [Array<String>, nil] [scheme, credentials] or nil if no auth
        def extract_authentication(request, context)
          # Try to extract from various sources
          
          # 1. Check context metadata for HTTP headers
          auth_header = context.get_metadata(:authorization) || 
                       context.get_metadata('Authorization')
          
          if auth_header
            return parse_authorization_header(auth_header)
          end
          
          # 2. Check request parameters for API key
          if request.params.is_a?(Hash)
            api_key = request.params['api_key'] || request.params[:api_key]
            if api_key
              return ['api_key', api_key]
            end
          end
          
          # 3. Check context for pre-set authentication
          if context.authenticated?
            # Return the first available authentication scheme
            context.instance_variable_get(:@auth_schemes)&.first
          end
          
          nil
        end

        ##
        # Parse Authorization header
        #
        # @param header [String] The Authorization header value
        # @return [Array<String>] [scheme, credentials]
        def parse_authorization_header(header)
          parts = header.strip.split(' ', 2)
          return nil if parts.length != 2
          
          scheme = parts[0].downcase
          credentials = parts[1]
          
          [scheme, credentials]
        end

        ##
        # Authenticate using the appropriate authenticator
        #
        # @param scheme [String] The authentication scheme
        # @param credentials [String] The credentials
        # @param context [A2A::Server::Context] The request context
        def authenticate(scheme, credentials, context)
          authenticator = @authenticators[scheme]
          
          unless authenticator
            raise A2A::Errors::AuthorizationFailed.new(
              "No authenticator configured for scheme '#{scheme}'"
            )
          end
          
          # Call the authenticator
          result = authenticator.call(credentials, context)
          
          if result
            # Set authentication in context
            context.set_authentication(scheme, result)
          else
            raise A2A::Errors::AuthorizationFailed.new(
              "Authentication failed for scheme '#{scheme}'"
            )
          end
        end

        ##
        # Default authenticator implementations
        #
        # @return [Hash] Hash of scheme name to authenticator proc
        def default_authenticators
          {
            'bearer' => method(:authenticate_bearer),
            'basic' => method(:authenticate_basic),
            'api_key' => method(:authenticate_api_key)
          }
        end

        ##
        # Authenticate Bearer token (JWT or API key)
        #
        # @param token [String] The bearer token
        # @param context [A2A::Server::Context] The request context
        # @return [Hash, nil] Authentication result or nil if invalid
        def authenticate_bearer(token, context)
          # This is a basic implementation - in practice you would:
          # 1. Validate JWT signature and expiration
          # 2. Check API key against database
          # 3. Extract user/session information
          
          # For now, just return the token as valid
          { token: token, scheme: 'bearer' }
        end

        ##
        # Authenticate Basic authentication
        #
        # @param credentials [String] Base64 encoded username:password
        # @param context [A2A::Server::Context] The request context
        # @return [Hash, nil] Authentication result or nil if invalid
        def authenticate_basic(credentials, context)
          begin
            decoded = Base64.decode64(credentials)
            username, password = decoded.split(':', 2)
            
            # In practice, validate against user database
            # For now, just return the username
            { username: username, scheme: 'basic' }
          rescue StandardError
            nil
          end
        end

        ##
        # Authenticate API key
        #
        # @param api_key [String] The API key
        # @param context [A2A::Server::Context] The request context
        # @return [Hash, nil] Authentication result or nil if invalid
        def authenticate_api_key(api_key, context)
          # In practice, validate against API key database
          # For now, just return the key as valid
          { api_key: api_key, scheme: 'api_key' }
        end
      end
    end
  end
end