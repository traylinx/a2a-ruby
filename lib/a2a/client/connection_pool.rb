# frozen_string_literal: true

require 'thread'
require 'monitor'

module A2A
  module Client
    ##
    # Connection pool manager for HTTP clients
    #
    # Manages a pool of HTTP connections to improve performance by reusing
    # connections and avoiding the overhead of establishing new connections
    # for each request.
    #
    class ConnectionPool
      include MonitorMixin

      # Default pool configuration
      DEFAULT_POOL_SIZE = 5
      DEFAULT_TIMEOUT = 5
      DEFAULT_IDLE_TIMEOUT = 30

      attr_reader :size, :timeout, :idle_timeout, :created, :checked_out

      ##
      # Initialize a new connection pool
      #
      # @param size [Integer] Maximum number of connections in the pool
      # @param timeout [Integer] Timeout for checking out a connection
      # @param idle_timeout [Integer] Timeout for idle connections
      # @yield Block that creates a new connection
      def initialize(size: DEFAULT_POOL_SIZE, timeout: DEFAULT_TIMEOUT, idle_timeout: DEFAULT_IDLE_TIMEOUT, &block)
        super()
        
        @size = size
        @timeout = timeout
        @idle_timeout = idle_timeout
        @connection_factory = block
        @pool = []
        @checked_out = []
        @created = 0
        @last_cleanup = Time.now
      end

      ##
      # Check out a connection from the pool
      #
      # @return [Object] A connection from the pool
      # @raise [TimeoutError] If no connection is available within timeout
      def checkout
        synchronize do
          connection = nil
          
          # Try to get an existing connection
          connection = @pool.pop
          
          # Create a new connection if pool is empty and we haven't reached the limit
          if connection.nil? && @created < @size
            connection = create_connection
          end
          
          # Wait for a connection to become available
          if connection.nil?
            deadline = Time.now + @timeout
            
            while connection.nil? && Time.now < deadline
              ns_wait(0.1) # Wait 100ms
              connection = @pool.pop
            end
            
            raise TimeoutError, "Could not checkout connection within #{@timeout}s" if connection.nil?
          end
          
          # Mark connection as checked out
          @checked_out << connection
          
          # Cleanup idle connections periodically
          cleanup_idle_connections if should_cleanup?
          
          connection
        end
      end

      ##
      # Check in a connection to the pool
      #
      # @param connection [Object] The connection to return to the pool
      def checkin(connection)
        synchronize do
          @checked_out.delete(connection)
          
          # Add connection back to pool if it's still valid
          if valid_connection?(connection)
            connection.instance_variable_set(:@last_used, Time.now)
            @pool.push(connection)
          else
            # Connection is invalid, create a new one to replace it
            @created -= 1
          end
        end
      end

      ##
      # Execute a block with a connection from the pool
      #
      # @yield [connection] Block to execute with the connection
      # @return [Object] Result of the block
      def with_connection
        connection = checkout
        begin
          yield connection
        ensure
          checkin(connection)
        end
      end

      ##
      # Get pool statistics
      #
      # @return [Hash] Pool statistics
      def stats
        synchronize do
          {
            size: @size,
            created: @created,
            available: @pool.size,
            checked_out: @checked_out.size,
            idle_timeout: @idle_timeout,
            timeout: @timeout
          }
        end
      end

      ##
      # Close all connections in the pool
      #
      def close_all
        synchronize do
          (@pool + @checked_out).each do |connection|
            close_connection(connection)
          end
          
          @pool.clear
          @checked_out.clear
          @created = 0
        end
      end

      ##
      # Flush idle connections from the pool
      #
      def flush_idle!
        synchronize do
          cleanup_idle_connections
        end
      end

      private

      ##
      # Create a new connection
      #
      # @return [Object] New connection
      def create_connection
        return nil unless @connection_factory
        
        connection = @connection_factory.call
        connection.instance_variable_set(:@created_at, Time.now)
        connection.instance_variable_set(:@last_used, Time.now)
        @created += 1
        
        connection
      end

      ##
      # Check if a connection is valid
      #
      # @param connection [Object] Connection to validate
      # @return [Boolean] True if connection is valid
      def valid_connection?(connection)
        return false unless connection
        
        # Check if connection responds to basic methods
        return false unless connection.respond_to?(:get) || connection.respond_to?(:request)
        
        # Check if connection is not too old
        created_at = connection.instance_variable_get(:@created_at)
        return false if created_at && (Time.now - created_at) > (@idle_timeout * 10)
        
        true
      rescue
        false
      end

      ##
      # Close a connection
      #
      # @param connection [Object] Connection to close
      def close_connection(connection)
        connection.close if connection.respond_to?(:close)
      rescue
        # Ignore errors when closing connections
      end

      ##
      # Check if we should run cleanup
      #
      # @return [Boolean] True if cleanup should run
      def should_cleanup?
        Time.now - @last_cleanup > 60 # Cleanup every minute
      end

      ##
      # Clean up idle connections
      #
      def cleanup_idle_connections
        @last_cleanup = Time.now
        cutoff_time = Time.now - @idle_timeout
        
        @pool.reject! do |connection|
          last_used = connection.instance_variable_get(:@last_used)
          if last_used && last_used < cutoff_time
            close_connection(connection)
            @created -= 1
            true
          else
            false
          end
        end
      end
    end

    ##
    # Timeout error for connection pool operations
    #
    class TimeoutError < StandardError; end
  end
end