# frozen_string_literal: true

require_relative 'middleware/authentication_middleware'
require_relative 'middleware/rate_limit_middleware'
require_relative 'middleware/logging_middleware'
require_relative 'middleware/cors_middleware'

module A2A
  module Server
    ##
    # Server middleware for A2A request processing
    #
    # This module provides various middleware components for A2A servers,
    # including authentication, rate limiting, logging, and CORS support.
    #
    # @example Using middleware with a handler
    #   handler = A2A::Server::Handler.new(agent)
    #   handler.add_middleware(A2A::Server::Middleware::AuthenticationMiddleware.new)
    #   handler.add_middleware(A2A::Server::Middleware::LoggingMiddleware.new)
    #
    module Middleware
      ##
      # Middleware registry for managing middleware instances
      #
      class Registry
        def initialize
          @middleware = []
        end

        ##
        # Add middleware to the registry
        #
        # @param middleware [Object] Middleware instance
        # @param options [Hash] Middleware options
        def add(middleware, **options)
          @middleware << { instance: middleware, options: options }
        end

        ##
        # Remove middleware from the registry
        #
        # @param middleware [Object] Middleware instance to remove
        def remove(middleware)
          @middleware.reject! { |m| m[:instance] == middleware }
        end

        ##
        # Get all middleware instances
        #
        # @return [Array] Array of middleware instances
        def all
          @middleware.map { |m| m[:instance] }
        end

        ##
        # Clear all middleware
        def clear
          @middleware.clear
        end

        ##
        # Get middleware count
        #
        # @return [Integer] Number of registered middleware
        def count
          @middleware.size
        end

        ##
        # Check if middleware is registered
        #
        # @param middleware [Object] Middleware instance to check
        # @return [Boolean] True if registered
        def include?(middleware)
          @middleware.any? { |m| m[:instance] == middleware }
        end

        ##
        # Execute middleware chain
        #
        # @param request [A2A::Protocol::Request] The request
        # @param context [A2A::Server::Context] The request context
        # @yield Block to execute after all middleware
        # @return [Object] Result from the block
        def call(request, context, &block)
          chain = block
          
          # Build middleware chain from the end backwards
          @middleware.reverse.each do |middleware_def|
            middleware = middleware_def[:instance]
            current_chain = chain
            
            chain = -> do
              if middleware.respond_to?(:call)
                middleware.call(request, context) { current_chain.call }
              else
                current_chain.call
              end
            end
          end
          
          # Execute the chain
          chain.call
        end
      end

      ##
      # Middleware builder for creating middleware stacks
      #
      class Builder
        def initialize
          @registry = Registry.new
        end

        ##
        # Add authentication middleware
        #
        # @param options [Hash] Authentication options
        def use_authentication(**options)
          @registry.add(AuthenticationMiddleware.new(**options))
          self
        end

        ##
        # Add rate limiting middleware
        #
        # @param options [Hash] Rate limiting options
        def use_rate_limiting(**options)
          @registry.add(RateLimitMiddleware.new(**options))
          self
        end

        ##
        # Add logging middleware
        #
        # @param options [Hash] Logging options
        def use_logging(**options)
          @registry.add(LoggingMiddleware.new(**options))
          self
        end

        ##
        # Add CORS middleware
        #
        # @param options [Hash] CORS options
        def use_cors(**options)
          @registry.add(CorsMiddleware.new(**options))
          self
        end

        ##
        # Add custom middleware
        #
        # @param middleware [Object] Middleware instance
        # @param options [Hash] Middleware options
        def use(middleware, **options)
          @registry.add(middleware, **options)
          self
        end

        ##
        # Build the middleware registry
        #
        # @return [Registry] The built middleware registry
        def build
          @registry
        end

        ##
        # Execute the middleware stack
        #
        # @param request [A2A::Protocol::Request] The request
        # @param context [A2A::Server::Context] The request context
        # @yield Block to execute after all middleware
        # @return [Object] Result from the block
        def call(request, context, &block)
          @registry.call(request, context, &block)
        end
      end

      ##
      # Create a new middleware builder
      #
      # @return [Builder] New middleware builder instance
      def self.build
        Builder.new
      end

      ##
      # Create a middleware stack with common middleware
      #
      # @param options [Hash] Configuration options
      # @return [Registry] Configured middleware registry
      def self.default_stack(**options)
        builder = build
        
        # Add logging by default
        builder.use_logging(options[:logging] || {})
        
        # Add authentication if configured
        if options[:authentication]
          builder.use_authentication(options[:authentication])
        end
        
        # Add rate limiting if configured
        if options[:rate_limiting]
          builder.use_rate_limiting(options[:rate_limiting])
        end
        
        # Add CORS if configured
        if options[:cors]
          builder.use_cors(options[:cors])
        end
        
        builder.build
      end
    end
  end
end