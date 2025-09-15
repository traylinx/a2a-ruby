# frozen_string_literal: true

module A2A
  module Client
    ##
    # Performance tracking functionality for HTTP clients
    #
    module PerformanceTracker
      ##
      # Initialize performance tracking
      #
      def initialize_performance_tracking
        @performance_stats = {
          requests_count: 0,
          total_time: 0.0,
          avg_response_time: 0.0,
          cache_hits: 0,
          cache_misses: 0
        }
        @stats_mutex = Mutex.new
      end

      ##
      # Get performance statistics
      #
      # @return [Hash] Performance statistics
      def performance_stats
        @stats_mutex.synchronize { @performance_stats.dup }
      end

      ##
      # Reset performance statistics
      #
      def reset_performance_stats!
        @stats_mutex.synchronize do
          @performance_stats = {
            requests_count: 0,
            total_time: 0.0,
            avg_response_time: 0.0,
            cache_hits: 0,
            cache_misses: 0
          }
        end
      end

      ##
      # Record request performance metrics
      #
      # @param duration [Float] Request duration in seconds
      def record_request_performance(duration)
        @stats_mutex.synchronize do
          @performance_stats[:requests_count] += 1
          @performance_stats[:total_time] += duration
          @performance_stats[:avg_response_time] =
            @performance_stats[:total_time] / @performance_stats[:requests_count]
        end
      end
    end
  end
end
