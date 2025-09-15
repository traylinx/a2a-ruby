# frozen_string_literal: true

module A2A
  module Utils
    ##
    # Performance optimization utilities
    #
    # Provides tools for profiling, memory optimization, and performance monitoring
    # across the A2A Ruby gem.
    #
    class Performance
      # Memory usage tracking
      @memory_snapshots = []
      @performance_data = {}

      class << self
        attr_reader :memory_snapshots, :performance_data

        ##
        # Profile a block of code and return execution time
        #
        # @param label [String] Label for the profiling session
        # @yield Block to profile
        # @return [Object] Result of the block
        def profile(label = 'operation')
          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          start_memory = memory_usage
          
          result = yield
          
          end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          end_memory = memory_usage
          
          duration = end_time - start_time
          memory_delta = end_memory - start_memory
          
          record_performance_data(label, duration, memory_delta)
          
          if A2A.configuration.performance_logging
            A2A.logger.info("Performance [#{label}]: #{duration.round(4)}s, Memory: #{format_bytes(memory_delta)}")
          end
          
          result
        end

        ##
        # Get current memory usage in bytes
        #
        # @return [Integer] Memory usage in bytes
        def memory_usage
          if defined?(GC.stat)
            # Use GC stats for more accurate memory tracking
            GC.stat(:heap_allocated_pages) * GC.stat(:heap_page_size)
          else
            # Fallback to process memory (less accurate)
            `ps -o rss= -p #{Process.pid}`.to_i * 1024
          end
        rescue
          0
        end

        ##
        # Take a memory snapshot
        #
        # @param label [String] Label for the snapshot
        def memory_snapshot(label = Time.now.to_s)
          snapshot = {
            label: label,
            timestamp: Time.now,
            memory: memory_usage,
            gc_stats: defined?(GC.stat) ? GC.stat : {}
          }
          
          @memory_snapshots << snapshot
          
          # Keep only last 100 snapshots
          @memory_snapshots = @memory_snapshots.last(100) if @memory_snapshots.size > 100
          
          snapshot
        end

        ##
        # Optimize garbage collection
        #
        def optimize_gc!
          return unless defined?(GC)
          
          # Force garbage collection
          GC.start
          
          # Compact heap if available (Ruby 2.7+)
          GC.compact if GC.respond_to?(:compact)
          
          # Tune GC settings for better performance
          if defined?(GC.tune)
            GC.tune(
              heap_growth_factor: 1.8,
              heap_growth_max_slots: 0,
              heap_init_slots: 10000,
              heap_free_slots: 4096,
              heap_oldobject_limit_factor: 2.0
            )
          end
        end

        ##
        # Optimize JSON parsing performance
        #
        # @param json_string [String] JSON string to parse
        # @return [Hash, Array] Parsed JSON
        def optimized_json_parse(json_string)
          # Use Oj if available for better performance
          if defined?(Oj)
            Oj.load(json_string, mode: :strict)
          else
            JSON.parse(json_string)
          end
        end

        ##
        # Optimize JSON generation performance
        #
        # @param object [Object] Object to serialize
        # @return [String] JSON string
        def optimized_json_generate(object)
          # Use Oj if available for better performance
          if defined?(Oj)
            Oj.dump(object, mode: :compat)
          else
            JSON.generate(object)
          end
        end

        ##
        # Create an optimized string buffer for large message handling
        #
        # @param initial_capacity [Integer] Initial buffer capacity
        # @return [StringIO] Optimized string buffer
        def create_string_buffer(initial_capacity = 8192)
          buffer = StringIO.new
          buffer.set_encoding(Encoding::UTF_8)
          
          # Pre-allocate capacity if possible
          if buffer.respond_to?(:capacity=)
            buffer.capacity = initial_capacity
          end
          
          buffer
        end

        ##
        # Batch process items for better performance
        #
        # @param items [Array] Items to process
        # @param batch_size [Integer] Size of each batch
        # @yield [Array] Block to process each batch
        # @return [Array] Results from all batches
        def batch_process(items, batch_size = 100)
          results = []
          
          items.each_slice(batch_size) do |batch|
            batch_result = yield(batch)
            results.concat(Array(batch_result))
          end
          
          results
        end

        ##
        # Get performance statistics
        #
        # @return [Hash] Performance statistics
        def statistics
          {
            memory_snapshots: @memory_snapshots.size,
            current_memory: memory_usage,
            performance_data: @performance_data,
            gc_stats: defined?(GC.stat) ? GC.stat : {}
          }
        end

        ##
        # Reset performance tracking data
        #
        def reset!
          @memory_snapshots.clear
          @performance_data.clear
        end

        ##
        # Check if performance optimizations are available
        #
        # @return [Hash] Available optimizations
        def available_optimizations
          {
            oj_json: defined?(Oj),
            gc_compact: defined?(GC) && GC.respond_to?(:compact),
            gc_tune: defined?(GC) && defined?(GC.tune),
            net_http_persistent: defined?(Net::HTTP::Persistent)
          }
        end

        private

        ##
        # Record performance data
        #
        # @param label [String] Operation label
        # @param duration [Float] Duration in seconds
        # @param memory_delta [Integer] Memory change in bytes
        def record_performance_data(label, duration, memory_delta)
          @performance_data[label] ||= {
            count: 0,
            total_time: 0.0,
            avg_time: 0.0,
            min_time: Float::INFINITY,
            max_time: 0.0,
            total_memory: 0,
            avg_memory: 0.0
          }
          
          data = @performance_data[label]
          data[:count] += 1
          data[:total_time] += duration
          data[:avg_time] = data[:total_time] / data[:count]
          data[:min_time] = [data[:min_time], duration].min
          data[:max_time] = [data[:max_time], duration].max
          data[:total_memory] += memory_delta
          data[:avg_memory] = data[:total_memory].to_f / data[:count]
        end

        ##
        # Format bytes for human-readable output
        #
        # @param bytes [Integer] Number of bytes
        # @return [String] Formatted string
        def format_bytes(bytes)
          return "0 B" if bytes == 0
          
          units = %w[B KB MB GB TB]
          exp = (Math.log(bytes.abs) / Math.log(1024)).floor
          exp = [exp, units.length - 1].min
          
          "#{(bytes / (1024.0 ** exp)).round(2)} #{units[exp]}"
        end
      end
    end
  end
end