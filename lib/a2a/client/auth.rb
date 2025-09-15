# frozen_string_literal: true

require_relative 'auth/oauth2'
require_relative 'auth/jwt'
require_relative 'auth/api_key'
require_relative 'auth/interceptor'

module A2A
  module Client
    ##
    # Authentication strategies and utilities for A2A clients
    #
    # This module provides various authentication mechanisms for communicating
    # with A2A agents, including OAuth 2.0, JWT, and API key authentication.
    #
    # @example OAuth 2.0 authentication
    #   oauth = A2A::Client::Auth::OAuth2.new(
    #     client_id: 'your-client-id',
    #     client_secret: 'your-client-secret',
    #     token_url: 'https://auth.example.com/oauth/token'
    #   )
    #   
    #   client = A2A::Client::HttpClient.new(
    #     'https://agent.example.com',
    #     middleware: [A2A::Client::Auth::Interceptor.new(oauth)]
    #   )
    #
    # @example JWT authentication
    #   jwt = A2A::Client::Auth::JWT.new(
    #     token: 'your-jwt-token'
    #   )
    #   
    #   interceptor = A2A::Client::Auth::Interceptor.new(jwt)
    #
    # @example API key authentication
    #   api_key = A2A::Client::Auth::ApiKey.new(
    #     key: 'your-api-key',
    #     name: 'X-API-Key',
    #     location: 'header'
    #   )
    #   
    #   interceptor = A2A::Client::Auth::Interceptor.new(api_key)
    #
    module Auth
      ##
      # Create authentication strategy from configuration
      #
      # @param config [Hash] Authentication configuration
      # @return [Object] Authentication strategy instance
      def self.from_config(config)
        case config['type'] || config[:type]
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
      end

      ##
      # Create authentication strategy from security scheme
      #
      # @param scheme [Hash] Security scheme definition from agent card
      # @param credentials [Hash] Authentication credentials
      # @return [Object] Authentication strategy instance
      def self.from_security_scheme(scheme, credentials)
        case scheme['type']
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
            # Basic auth configuration
            {
              type: 'basic',
              username: credentials['username'],
              password: credentials['password']
            }
          else
            raise ArgumentError, "Unsupported HTTP scheme: #{scheme['scheme']}"
          end
        when 'apiKey'
          ApiKey.from_security_scheme(scheme, credentials['key'])
        else
          raise ArgumentError, "Unsupported security scheme type: #{scheme['type']}"
        end
      end

      ##
      # Create interceptor from configuration
      #
      # @param config [Hash] Authentication configuration
      # @return [Interceptor] Configured authentication interceptor
      def self.interceptor_from_config(config)
        strategy = from_config(config)
        Interceptor.new(strategy, auto_retry: config['auto_retry'] || config[:auto_retry] || true)
      end

      ##
      # Create interceptor from security scheme
      #
      # @param scheme [Hash] Security scheme definition
      # @param credentials [Hash] Authentication credentials
      # @return [Interceptor] Configured authentication interceptor
      def self.interceptor_from_security_scheme(scheme, credentials)
        strategy = from_security_scheme(scheme, credentials)
        Interceptor.new(strategy)
      end
    end
  end
end