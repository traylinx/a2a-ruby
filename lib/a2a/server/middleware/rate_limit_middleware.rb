# frozen_string_literal: true

require_relative '../../errors'

module A2A
  module Server
    module Middleware
      ##
      # Rate limiting middleware for A2A requests
      #
      # Implements rate limiting using various strategies including
      # in-memory, Redis-backed, and sliding window algorithms.
      #
      # @example Basic usage
      #   middleware = RateLimitMiddleware.new(
      #     limit: 100,
      #     window: 3600, # 1 hour
      #     strategy: :sliding_window
      #   )
      #
      class RateLimitMiddleware
        attr_reader :limit, :window, :strategy, :store

        # Rate limiting strategies
        STRATEGIES = [:fixed_window, :sliding_window, :token_bucket].freeze

        ##
        # Initialize rate limiting middleware
        #
        # @param limit [Integer] Maximum number of requests per window
        # @param window [Integer] Time window in seconds
        # @param strategy [Symbol] Rate limiting strategy
        # @param store [Object] Storage backend (defaults to in-memory)
        # @param key_generator [Proc] Custom key generator for rate limiting
        def initialize(limit: 100, window: 3600, strategy: :sliding_window, 
                       store: nil, key_generator: nil)
          @limit = limit
          @window = window
          @strategy = strategy
          @store = store || InMemoryStore.new
          @key_generator = key_generator || method(:default_key_generator)
          
          validate_strategy!
        end

        ##
        # Process rate limiting for a request
        #
        # @param request [A2A::Protocol::Request] The JSON-RPC request
        # @param context [A2A::Server::Context] The request context
        # @yield Block to continue the middleware chain
        # @return [Object] The result from the next middleware or handler
        # @raise [A2A::Errors::RateLimitExceeded] If rate limit is exceeded
        def call(request, context)
          # Generate rate limiting key
          key = @key_generator.call(request, context)
          
          # Check rate limit
          unless check_rate_limit(key)
            raise A2A::Errors::RateLimitExceeded.new(
              "Rate limit exceeded: #{@limit} requests per #{@window} seconds"
            )
          end
          
          # Continue to next middleware
          yield
        end

        ##
        # Check if request is within rate limit
        #
        # @param key [String] The rate limiting key
        # @return [Boolean] True if within limit, false otherwise
        def check_rate_limit(key)
          case @strategy
          when :fixed_window
            check_fixed_window(key)
          when :sliding_window
            check_sliding_window(key)
          when :token_bucket
            check_token_bucket(key)
          else
            true # Fallback to allow request
          end
        end

        ##
        # Get current rate limit status for a key
        #
        # @param key [String] The rate limiting key
        # @return [Hash] Status information
        def status(key)
          case @strategy
          when :fixed_window
            fixed_window_status(key)
          when :sliding_window
            sliding_window_status(key)
          when :token_bucket
            token_bucket_status(key)
          else
            { limit: @limit, remaining: @limit, reset_time: nil }
          end
        end

        private

        ##
        # Validate the rate limiting strategy
        def validate_strategy!
          unless STRATEGIES.include?(@strategy)
            raise ArgumentError, "Invalid strategy: #{@strategy}. Must be one of: #{STRATEGIES.join(', ')}"
          end
        end

        ##
        # Default key generator based on authentication or IP
        #
        # @param request [A2A::Protocol::Request] The request
        # @param context [A2A::Server::Context] The context
        # @return [String] The rate limiting key
        def default_key_generator(request, context)
          # Try to use authenticated user/API key
          if context.authenticated?
            auth_data = context.instance_variable_get(:@auth_schemes)&.values&.first
            if auth_data.is_a?(Hash)
              return "user:#{auth_data[:username] || auth_data[:api_key] || auth_data[:token]}"
            end
          end
          
          # Fall back to IP address if available
          ip = context.get_metadata(:remote_ip) || context.get_metadata('REMOTE_ADDR')
          return "ip:#{ip}" if ip
          
          # Default fallback
          "anonymous"
        end

        ##
        # Fixed window rate limiting
        #
        # @param key [String] The rate limiting key
        # @return [Boolean] True if within limit
        def check_fixed_window(key)
          now = Time.now.to_i
          window_start = (now / @window) * @window
          window_key = "#{key}:#{window_start}"
          
          current_count = @store.get(window_key) || 0
          
          if current_count >= @limit
            false
          else
            @store.increment(window_key, expires_at: window_start + @window)
            true
          end
        end

        ##
        # Sliding window rate limiting
        #
        # @param key [String] The rate limiting key
        # @return [Boolean] True if within limit
        def check_sliding_window(key)
          now = Time.now.to_f
          window_start = now - @window
          
          # Get timestamps of requests in the current window
          timestamps = @store.get_list("#{key}:timestamps") || []
          
          # Remove old timestamps
          timestamps = timestamps.select { |ts| ts > window_start }
          
          if timestamps.length >= @limit
            false
          else
            # Add current timestamp
            timestamps << now
            @store.set_list("#{key}:timestamps", timestamps, expires_at: now + @window)
            true
          end
        end

        ##
        # Token bucket rate limiting
        #
        # @param key [String] The rate limiting key
        # @return [Boolean] True if within limit
        def check_token_bucket(key)
          now = Time.now.to_f
          bucket_key = "#{key}:bucket"
          
          # Get current bucket state
          bucket = @store.get(bucket_key) || { tokens: @limit, last_refill: now }
          
          # Calculate tokens to add based on time elapsed
          time_elapsed = now - bucket[:last_refill]
          tokens_to_add = (time_elapsed / @window) * @limit
          
          # Refill bucket
          bucket[:tokens] = [@limit, bucket[:tokens] + tokens_to_add].min
          bucket[:last_refill] = now
          
          if bucket[:tokens] >= 1
            bucket[:tokens] -= 1
            @store.set(bucket_key, bucket, expires_at: now + @window * 2)
            true
          else
            @store.set(bucket_key, bucket, expires_at: now + @window * 2)
            false
          end
        end

        ##
        # Get fixed window status
        def fixed_window_status(key)
          now = Time.now.to_i
          window_start = (now / @window) * @window
          window_key = "#{key}:#{window_start}"
          
          current_count = @store.get(window_key) || 0
          reset_time = window_start + @window
          
          {
            limit: @limit,
            remaining: [@limit - current_count, 0].max,
            reset_time: Time.at(reset_time),
            window_start: Time.at(window_start)
          }
        end

        ##
        # Get sliding window status
        def sliding_window_status(key)
          now = Time.now.to_f
          window_start = now - @window
          
          timestamps = @store.get_list("#{key}:timestamps") || []
          current_count = timestamps.count { |ts| ts > window_start }
          
          {
            limit: @limit,
            remaining: [@limit - current_count, 0].max,
            reset_time: nil, # No fixed reset time for sliding window
            window_start: Time.at(window_start)
          }
        end

        ##
        # Get token bucket status
        def token_bucket_status(key)
          now = Time.now.to_f
          bucket_key = "#{key}:bucket"
          
          bucket = @store.get(bucket_key) || { tokens: @limit, last_refill: now }
          
          # Calculate current tokens
          time_elapsed = now - bucket[:last_refill]
          tokens_to_add = (time_elapsed / @window) * @limit
          current_tokens = [@limit, bucket[:tokens] + tokens_to_add].min
          
          {
            limit: @limit,
            remaining: current_tokens.floor,
            reset_time: nil, # Continuous refill
            tokens: current_tokens
          }
        end
      end

      ##
      # In-memory storage for rate limiting
      #
      class InMemoryStore
        def initialize
          @data = {}
          @mutex = Mutex.new
        end

        def get(key)
          @mutex.synchronize do
            entry = @data[key]
            return nil unless entry
            
            # Check expiration
            if entry[:expires_at] && Time.now.to_f > entry[:expires_at]
              @data.delete(key)
              return nil
            end
            
            entry[:value]
          end
        end

        def set(key, value, expires_at: nil)
          @mutex.synchronize do
            @data[key] = {
              value: value,
              expires_at: expires_at
            }
          end
        end

        def increment(key, expires_at: nil)
          @mutex.synchronize do
            entry = @data[key] || { value: 0, expires_at: expires_at }
            
            # Check expiration
            if entry[:expires_at] && Time.now.to_f > entry[:expires_at]
              entry = { value: 0, expires_at: expires_at }
            end
            
            entry[:value] += 1
            entry[:expires_at] = expires_at if expires_at
            @data[key] = entry
            
            entry[:value]
          end
        end

        def get_list(key)
          get(key)
        end

        def set_list(key, list, expires_at: nil)
          set(key, list, expires_at: expires_at)
        end

        def clear
          @mutex.synchronize do
            @data.clear
          end
        end

        def size
          @mutex.synchronize do
            @data.size
          end
        end
      end

      ##
      # Redis-backed storage for rate limiting
      #
      class RedisStore
        def initialize(redis_client)
          @redis = redis_client
        end

        def get(key)
          value = @redis.get(key)
          value ? JSON.parse(value) : nil
        rescue JSON::ParserError
          nil
        end

        def set(key, value, expires_at: nil)
          json_value = JSON.generate(value)
          
          if expires_at
            ttl = (expires_at - Time.now.to_f).ceil
            @redis.setex(key, ttl, json_value) if ttl > 0
          else
            @redis.set(key, json_value)
          end
        end

        def increment(key, expires_at: nil)
          result = @redis.incr(key)
          
          if expires_at && result == 1
            ttl = (expires_at - Time.now.to_f).ceil
            @redis.expire(key, ttl) if ttl > 0
          end
          
          result
        end

        def get_list(key)
          get(key)
        end

        def set_list(key, list, expires_at: nil)
          set(key, list, expires_at: expires_at)
        end
      end
    end
  end
end