# frozen_string_literal: true

##
# CORS (Cross-Origin Resource Sharing) middleware for A2A requests
#
# Handles CORS headers for A2A JSON-RPC requests to enable
# cross-origin requests from web browsers.
#
# @example Basic usage
#   middleware = CorsMiddleware.new(
#     origins: ['https://example.com'],
#     methods: ['POST', 'OPTIONS'],
#     headers: ['Content-Type', 'Authorization']
#   )
#
module A2A
  module Server
    module Middleware
      class CorsMiddleware
        attr_reader :origins, :methods, :headers, :credentials, :max_age

        ##
        # Initialize CORS middleware
        #
        # @param origins [Array<String>, String] Allowed origins (* for all)
        # @param methods [Array<String>] Allowed HTTP methods
        # @param headers [Array<String>] Allowed headers
        # @param credentials [Boolean] Whether to allow credentials
        # @param max_age [Integer] Preflight cache duration in seconds
        # @param expose_headers [Array<String>] Headers to expose to client
        def initialize(origins: "*", methods: %w[POST OPTIONS],
                       headers: %w[Content-Type Authorization],
                       credentials: false, max_age: 86_400, expose_headers: [])
          @origins = normalize_origins(origins)
          @methods = Array(methods).map(&:upcase)
          @headers = Array(headers)
          @credentials = credentials
          @max_age = max_age
          @expose_headers = Array(expose_headers)
        end

        ##
        # Process CORS for a request
        #
        # @param request [A2A::Protocol::Request] The JSON-RPC request
        # @param context [A2A::Server::Context] The request context
        # @yield Block to continue the middleware chain
        # @return [Object] The result from the next middleware or handler
        def call(_request, context)
          # Extract HTTP method and origin from context
          http_method = context.get_metadata(:http_method) || "POST"
          origin = context.get_metadata(:origin) || context.get_metadata("Origin")

          # Handle preflight requests
          return handle_preflight(origin, context) if http_method.casecmp("OPTIONS").zero?

          # Add CORS headers to the response
          add_cors_headers(origin, context)

          # Continue to next middleware
          yield
        end

        ##
        # Check if an origin is allowed
        #
        # @param origin [String] The origin to check
        # @return [Boolean] True if origin is allowed
        def origin_allowed?(origin)
          return true if @origins == "*"
          return false if origin.nil?

          @origins.any? do |allowed_origin|
            if allowed_origin.include?("*")
              # Handle wildcard patterns
              pattern = Regexp.escape(allowed_origin).gsub('\*', ".*")
              origin.match?(/\A#{pattern}\z/)
            else
              origin == allowed_origin
            end
          end
        end

        ##
        # Get CORS headers for an origin
        #
        # @param origin [String] The request origin
        # @return [Hash] CORS headers
        def cors_headers(origin)
          headers = {}

          if origin_allowed?(origin)
            headers["Access-Control-Allow-Origin"] = @origins == "*" ? "*" : origin

            headers["Access-Control-Allow-Credentials"] = "true" if @credentials

            headers["Access-Control-Expose-Headers"] = @expose_headers.join(", ") unless @expose_headers.empty?
          end

          headers
        end

        ##
        # Get preflight CORS headers
        #
        # @param origin [String] The request origin
        # @return [Hash] Preflight CORS headers
        def preflight_headers(origin)
          headers = cors_headers(origin)

          if origin_allowed?(origin)
            headers["Access-Control-Allow-Methods"] = @methods.join(", ")
            headers["Access-Control-Allow-Headers"] = @headers.join(", ")
            headers["Access-Control-Max-Age"] = @max_age.to_s
          end

          headers
        end

        private

        ##
        # Normalize origins configuration
        #
        # @param origins [Array, String] Origins configuration
        # @return [Array<String>, String] Normalized origins
        def normalize_origins(origins)
          case origins
          when String
            origins == "*" ? "*" : [origins]
          when Array
            origins.include?("*") ? "*" : origins
          else
            ["*"]
          end
        end

        ##
        # Handle preflight OPTIONS request
        #
        # @param origin [String] The request origin
        # @param context [A2A::Server::Context] The request context
        # @return [Hash] Preflight response
        def handle_preflight(origin, context)
          # Add preflight headers to context for response
          preflight_headers(origin).each do |key, value|
            context.set_metadata("response_header_#{key.downcase}", value)
          end

          # Return empty response for preflight
          {
            status: 200,
            headers: preflight_headers(origin),
            body: ""
          }
        end

        ##
        # Add CORS headers to response context
        #
        # @param origin [String] The request origin
        # @param context [A2A::Server::Context] The request context
        def add_cors_headers(origin, context)
          cors_headers(origin).each do |key, value|
            context.set_metadata("response_header_#{key.downcase}", value)
          end
        end
      end
    end
  end
end
