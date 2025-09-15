# frozen_string_literal: true

require_relative 'oauth2'
require_relative 'jwt'
require_relative 'api_key'

module A2A
  module Client
    module Auth
      ##
      # Authentication interceptor for automatic token handling
      #
      # Provides a unified interface for applying different authentication
      # strategies to HTTP requests, with automatic token refresh and
      # error handling.
      #
      class Interceptor
        attr_reader :strategy, :auto_retry

        ##
        # Initialize authentication interceptor
        #
        # @param strategy [Object] Authentication strategy (OAuth2, JWT, ApiKey, etc.)
        # @param auto_retry [Boolean] Whether to automatically retry on auth failures
        def initialize(strategy, auto_retry: true)
          @strategy = strategy
          @auto_retry = auto_retry
          @retry_mutex = Mutex.new
        end

        ##
        # Middleware call method for Faraday
        #
        # @param request [Object] The request object
        # @param context [Hash] Request context
        # @param next_middleware [Proc] Next middleware in chain
        # @return [Object] Response from next middleware
        def call(request, context, next_middleware)
          # Apply authentication to the request
          apply_authentication(request)

          # Execute the request
          begin
            response = next_middleware.call(request, context)
            
            # Check for authentication errors and retry if configured
            if authentication_error?(response) && @auto_retry
              handle_auth_error_retry(request, context, next_middleware)
            else
              response
            end
          rescue A2A::Errors::AuthenticationError, A2A::Errors::AuthorizationFailed => e
            if @auto_retry
              handle_auth_error_retry(request, context, next_middleware)
            else
              raise e
            end
          end
        end

        ##
        # Apply authentication to a request
        #
        # @param request [Object] The request to authenticate
        def apply_authentication(request)
          case @strategy
          when OAuth2, JWT, ApiKey
            @strategy.apply_to_request(request)
          when Hash
            # Handle configuration-based authentication
            apply_config_authentication(request, @strategy)
          else
            raise ArgumentError, "Unsupported authentication strategy: #{@strategy.class}"
          end
        end

        ##
        # Create interceptor from configuration
        #
        # @param config [Hash] Authentication configuration
        # @return [Interceptor] Configured interceptor
        def self.from_config(config)
          strategy = case config['type'] || config[:type]
                    when 'oauth2'
                      OAuth2.new(
                        client_id: config['client_id'] || config[:client_id],
                        client_secret: config['client_secret'] || config[:client_secret],
                        token_url: config['token_url'] || config[:token_url],
                        scope: config['scope'] || config[:scope]
                      )
                    when 'jwt'
                      JWT.new(
                        token: config['token'] || config[:token],
                        secret: config['secret'] || config[:secret],
                        algorithm: config['algorithm'] || config[:algorithm] || 'HS256',
                        payload: config['payload'] || config[:payload],
                        headers: config['headers'] || config[:headers],
                        expires_in: config['expires_in'] || config[:expires_in]
                      )
                    when 'api_key'
                      ApiKey.new(
                        key: config['key'] || config[:key],
                        name: config['name'] || config[:name] || 'X-API-Key',
                        location: config['location'] || config[:location] || 'header'
                      )
                    else
                      raise ArgumentError, "Unknown authentication type: #{config['type'] || config[:type]}"
                    end

          new(strategy, auto_retry: config['auto_retry'] || config[:auto_retry] || true)
        end

        ##
        # Create interceptor from security scheme
        #
        # @param scheme [Hash] Security scheme definition
        # @param credentials [Hash] Authentication credentials
        # @return [Interceptor] Configured interceptor
        def self.from_security_scheme(scheme, credentials)
          strategy = case scheme['type']
                    when 'oauth2'
                      OAuth2.new(
                        client_id: credentials['client_id'],
                        client_secret: credentials['client_secret'],
                        token_url: scheme['tokenUrl'],
                        scope: credentials['scope']
                      )
                    when 'http'
                      case scheme['scheme']
                      when 'bearer'
                        JWT.new(token: credentials['token'])
                      when 'basic'
                        # Basic auth would be handled differently
                        raise ArgumentError, "Basic auth not yet implemented"
                      else
                        raise ArgumentError, "Unsupported HTTP scheme: #{scheme['scheme']}"
                      end
                    when 'apiKey'
                      ApiKey.from_security_scheme(scheme, credentials['key'])
                    else
                      raise ArgumentError, "Unsupported security scheme type: #{scheme['type']}"
                    end

          new(strategy)
        end

        ##
        # Check if the strategy supports token refresh
        #
        # @return [Boolean] True if strategy supports refresh
        def supports_refresh?
          @strategy.respond_to?(:refresh_token!) || @strategy.respond_to?(:regenerate_token!)
        end

        ##
        # Refresh authentication credentials
        #
        # @return [Boolean] True if refresh was successful
        def refresh!
          return false unless supports_refresh?

          begin
            if @strategy.respond_to?(:refresh_token!)
              @strategy.refresh_token!
            elsif @strategy.respond_to?(:regenerate_token!)
              @strategy.regenerate_token!
            end
            true
          rescue => e
            false
          end
        end

        ##
        # Get current authentication status
        #
        # @return [Hash] Status information
        def status
          {
            strategy: @strategy.class.name,
            valid: strategy_valid?,
            supports_refresh: supports_refresh?,
            expires_at: strategy_expires_at
          }
        end

        private

        ##
        # Apply configuration-based authentication
        #
        # @param request [Object] The request to authenticate
        # @param config [Hash] Authentication configuration
        def apply_config_authentication(request, config)
          case config['type'] || config[:type]
          when 'bearer'
            request.headers['Authorization'] = "Bearer #{config['token'] || config[:token]}"
          when 'basic'
            require 'base64'
            username = config['username'] || config[:username]
            password = config['password'] || config[:password]
            credentials = Base64.strict_encode64("#{username}:#{password}")
            request.headers['Authorization'] = "Basic #{credentials}"
          when 'api_key'
            name = config['name'] || config[:name] || 'X-API-Key'
            key = config['key'] || config[:key]
            location = config['location'] || config[:location] || 'header'
            
            case location
            when 'header'
              request.headers[name] = key
            when 'query'
              request.params[name] = key
            end
          end
        end

        ##
        # Check if response indicates authentication error
        #
        # @param response [Object] The response to check
        # @return [Boolean] True if authentication error
        def authentication_error?(response)
          # This would depend on the response format
          # For HTTP responses, check status codes
          if response.respond_to?(:status)
            return response.status == 401 || response.status == 403
          end

          # For JSON-RPC responses, check error codes
          if response.respond_to?(:[]) && response['error']
            error_code = response['error']['code']
            return error_code == A2A::Protocol::JsonRpc::AUTHENTICATION_REQUIRED ||
                   error_code == A2A::Protocol::JsonRpc::AUTHORIZATION_FAILED
          end

          false
        end

        ##
        # Handle authentication error with retry
        #
        # @param request [Object] The original request
        # @param context [Hash] Request context
        # @param next_middleware [Proc] Next middleware in chain
        # @return [Object] Response from retry attempt
        def handle_auth_error_retry(request, context, next_middleware)
          @retry_mutex.synchronize do
            # Try to refresh credentials
            if refresh!
              # Reapply authentication and retry
              apply_authentication(request)
              return next_middleware.call(request, context)
            end
          end

          # If refresh failed, raise the original error
          raise A2A::Errors::AuthenticationError.new("Authentication failed and refresh unsuccessful")
        end

        ##
        # Check if the current strategy is valid
        #
        # @return [Boolean] True if strategy is valid
        def strategy_valid?
          case @strategy
          when OAuth2
            @strategy.token_valid?
          when JWT
            !@strategy.token_expired?
          when ApiKey
            @strategy.valid?
          else
            true # Assume valid for unknown strategies
          end
        end

        ##
        # Get strategy expiration time
        #
        # @return [Time, nil] Expiration time if available
        def strategy_expires_at
          case @strategy
          when OAuth2
            @strategy.expires_at
          when JWT
            @strategy.expires_at
          else
            nil
          end
        end
      end
    end
  end
end