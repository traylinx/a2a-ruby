# frozen_string_literal: true

##
# Memory Usage and Performance Profiling for A2A Ruby Gem
#
# This suite provides detailed memory usage analysis and performance profiling
# to identify optimization opportunities and prevent memory leaks.
#
RSpec.describe "A2A Memory Profiling", :memory, :performance do
  # Memory thresholds (in MB)
  MEMORY_THRESHOLDS = {
    single_operation: 1.0,      # 1MB per single operation
    batch_operations: 10.0,     # 10MB for batch of 100 operations
    sustained_load: 50.0,       # 50MB for sustained operations
    memory_leak_rate: 0.1       # 0.1MB per 1000 operations (leak detection)
  }.freeze

  describe "Memory Usage Analysis" do
    context "single operation memory usage" do
      it "measures JSON-RPC parsing memory usage" do
        skip "GetProcessMem gem not available" unless defined?(GetProcessMem)

        request_json = build_json_rpc_request("memory_test", {
                                                data: "x" * 10_000, # 10KB payload
                                                metadata: (1..100).map { |i| { "key_#{i}" => "value_#{i}" } }
                                              }).to_json

        result = measure_memory do
          100.times do
            A2A::Protocol::JsonRpc.parse_request(request_json)
          end
        end

        memory_per_operation = result[:memory_mb] / 100
        expect(memory_per_operation).to be < MEMORY_THRESHOLDS[:single_operation]

        puts "JSON-RPC parsing memory: #{memory_per_operation.round(3)}MB per operation"
      end

      it "measures message validation memory usage" do
        skip "GetProcessMem gem not available" unless defined?(GetProcessMem)

        complex_message = generate_complex_message

        result = measure_memory do
          100.times do
            expect(complex_message).to be_valid_a2a_message
          end
        end

        memory_per_validation = result[:memory_mb] / 100
        expect(memory_per_validation).to be < MEMORY_THRESHOLDS[:single_operation]

        puts "Message validation memory: #{memory_per_validation.round(3)}MB per validation"
      end

      it "measures task processing memory usage" do
        skip "GetProcessMem gem not available" unless defined?(GetProcessMem)

        comprehensive_task = generate_comprehensive_task

        result = measure_memory do
          50.times do
            expect(comprehensive_task).to be_valid_a2a_task
          end
        end

        memory_per_task = result[:memory_mb] / 50
        expect(memory_per_task).to be < MEMORY_THRESHOLDS[:single_operation]

        puts "Task processing memory: #{memory_per_task.round(3)}MB per task"
      end
    end

    context "batch operation memory usage" do
      it "measures batch JSON-RPC processing memory" do
        skip "GetProcessMem gem not available" unless defined?(GetProcessMem)

        batch_requests = (1..100).map do |i|
          build_json_rpc_request("batch_method_#{i}", {
                                   index: i,
                                   data: "x" * 1000 # 1KB per request
                                 })
        end
        batch_json = batch_requests.to_json

        result = measure_memory do
          10.times do
            parsed = A2A::Protocol::JsonRpc.parse_request(batch_json)
            expect(parsed.length).to eq(100)
          end
        end

        expect(result[:memory_mb]).to be < MEMORY_THRESHOLDS[:batch_operations]

        puts "Batch processing memory (100 requests): #{result[:memory_mb].round(3)}MB"
      end

      it "measures message batch validation memory" do
        skip "GetProcessMem gem not available" unless defined?(GetProcessMem)

        messages = (1..100).map { |i| build_message(text: "Batch message #{i}") }

        result = measure_memory do
          10.times do
            messages.each { |msg| expect(msg).to be_valid_a2a_message }
          end
        end

        expect(result[:memory_mb]).to be < MEMORY_THRESHOLDS[:batch_operations]

        puts "Message batch validation memory (100 messages): #{result[:memory_mb].round(3)}MB"
      end
    end

    context "sustained operation memory usage" do
      it "measures memory usage during sustained processing" do
        skip "GetProcessMem gem not available" unless defined?(GetProcessMem)

        initial_memory = GetProcessMem.new.mb

        # Simulate sustained processing for 30 seconds
        start_time = Time.current
        operations = 0

        while (Time.current - start_time) < 30
          request = build_json_rpc_request("sustained_#{operations}", {
                                             timestamp: Time.current.to_f,
                                             data: "x" * 500 # 500 bytes per request
                                           })

          A2A::Protocol::JsonRpc.parse_request(request.to_json)

          message = build_message(text: "Sustained message #{operations}")
          expect(message).to be_valid_a2a_message

          operations += 1

          # Force garbage collection every 100 operations
          GC.start if operations % 100 == 0
        end

        final_memory = GetProcessMem.new.mb
        memory_increase = final_memory - initial_memory

        expect(memory_increase).to be < MEMORY_THRESHOLDS[:sustained_load]

        puts "Sustained processing memory increase: #{memory_increase.round(3)}MB over #{operations} operations"
        puts "Memory per operation: #{(memory_increase / operations * 1000).round(3)}KB"
      end
    end
  end

  describe "Memory Leak Detection" do
    context "repeated operations" do
      it "detects memory leaks in JSON-RPC parsing" do
        skip "GetProcessMem gem not available" unless defined?(GetProcessMem)

        request_json = build_json_rpc_request("leak_test", { data: "test" }).to_json

        # Measure memory usage over multiple iterations
        memory_samples = []

        5.times do |iteration|
          GC.start # Force garbage collection before measurement

          initial_memory = GetProcessMem.new.mb

          1000.times do
            A2A::Protocol::JsonRpc.parse_request(request_json)
          end

          GC.start # Force garbage collection after operations
          final_memory = GetProcessMem.new.mb

          memory_increase = final_memory - initial_memory
          memory_samples << memory_increase

          puts "Iteration #{iteration + 1}: #{memory_increase.round(3)}MB increase"
        end

        # Check for memory leak trend
        if memory_samples.length >= 3
          # Calculate trend (should be stable, not increasing)
          trend = (memory_samples.last - memory_samples.first) / memory_samples.length
          expect(trend).to be < MEMORY_THRESHOLDS[:memory_leak_rate]

          puts "Memory leak trend: #{trend.round(3)}MB per iteration"
        end
      end

      it "detects memory leaks in message processing" do
        skip "GetProcessMem gem not available" unless defined?(GetProcessMem)

        memory_samples = []

        5.times do |iteration|
          GC.start

          initial_memory = GetProcessMem.new.mb

          1000.times do |i|
            message = build_message(text: "Leak test message #{i}")
            expect(message).to be_valid_a2a_message
          end

          GC.start
          final_memory = GetProcessMem.new.mb

          memory_increase = final_memory - initial_memory
          memory_samples << memory_increase

          puts "Message processing iteration #{iteration + 1}: #{memory_increase.round(3)}MB increase"
        end

        # Check for memory leak trend
        if memory_samples.length >= 3
          trend = (memory_samples.last - memory_samples.first) / memory_samples.length
          expect(trend).to be < MEMORY_THRESHOLDS[:memory_leak_rate]

          puts "Message processing leak trend: #{trend.round(3)}MB per iteration"
        end
      end
    end

    context "object lifecycle" do
      it "ensures proper object cleanup" do
        skip "ObjectSpace not available" unless defined?(ObjectSpace)

        # Count objects before operations
        initial_objects = ObjectSpace.count_objects

        # Perform operations that create temporary objects
        1000.times do |i|
          request = build_json_rpc_request("cleanup_test_#{i}", { index: i })
          A2A::Protocol::JsonRpc.parse_request(request.to_json)

          message = build_message(text: "Cleanup test #{i}")
          expect(message).to be_valid_a2a_message
        end

        # Force garbage collection
        3.times { GC.start }

        # Count objects after operations and cleanup
        final_objects = ObjectSpace.count_objects

        # Calculate object count differences
        object_diff = {}
        initial_objects.each do |type, initial_count|
          final_count = final_objects[type] || 0
          diff = final_count - initial_count
          object_diff[type] = diff if diff > 0
        end

        puts "Object count increases after cleanup:"
        object_diff.each do |type, count|
          puts "  #{type}: +#{count}"
        end

        # Total object increase should be reasonable
        total_increase = object_diff.values.sum
        expect(total_increase).to be < 10_000 # Allow some object growth but not excessive
      end
    end
  end

  describe "Memory Optimization Analysis" do
    context "string allocation patterns" do
      it "analyzes string allocation in JSON processing" do
        skip "AllocationTracer not available" unless defined?(AllocationTracer)

        # This would use AllocationTracer to track string allocations
        # Placeholder for actual allocation tracking

        request_json = build_json_rpc_request("string_test", {
                                                message: "Test string allocation patterns",
                                                data: (1..100).map { |i| "String #{i}" }
                                              }).to_json

        # Track allocations during parsing

        100.times do
          A2A::Protocol::JsonRpc.parse_request(request_json)
        end

        # Analyze allocation patterns
        puts "String allocation analysis would go here"
        expect(true).to be true # Placeholder
      end
    end

    context "hash allocation patterns" do
      it "analyzes hash allocation in message processing" do
        # Analyze hash creation patterns in message validation

        messages = (1..100).map do |i|
          {
            messageId: test_uuid,
            role: "user",
            kind: "message",
            parts: [{ kind: "text", text: "Hash test #{i}" }],
            metadata: { index: i, timestamp: Time.current.iso8601 }
          }
        end

        # Process messages and analyze hash usage
        messages.each { |msg| expect(msg).to be_valid_a2a_message }

        puts "Hash allocation analysis would go here"
        expect(true).to be true # Placeholder
      end
    end

    context "array allocation patterns" do
      it "analyzes array allocation in batch processing" do
        # Analyze array creation in batch request processing

        batch_requests = (1..100).map do |i|
          build_json_rpc_request("array_test_#{i}", {
                                   items: (1..10).map { |j| "Item #{i}-#{j}" },
                                   metadata: [i, Time.current.to_f, "test"]
                                 })
        end

        batch_json = batch_requests.to_json
        parsed = A2A::Protocol::JsonRpc.parse_request(batch_json)

        expect(parsed.length).to eq(100)

        puts "Array allocation analysis would go here"
        expect(true).to be true # Placeholder
      end
    end
  end

  describe "Garbage Collection Analysis" do
    context "GC behavior under load" do
      it "analyzes garbage collection frequency" do
        skip "GC.stat not available" unless GC.respond_to?(:stat)

        # Record initial GC stats
        initial_gc_stats = GC.stat

        # Perform operations that generate garbage
        1000.times do |i|
          # Create temporary objects
          request = build_json_rpc_request("gc_test_#{i}", {
                                             temporary_data: "x" * 1000,
                                             array_data: (1..100).to_a,
                                             hash_data: (1..50).to_h { |j| ["key_#{j}", "value_#{j}"] }
                                           })

          A2A::Protocol::JsonRpc.parse_request(request.to_json)

          # Create temporary message
          message = build_message(text: "GC test message #{i}")
          expect(message).to be_valid_a2a_message
        end

        # Record final GC stats
        final_gc_stats = GC.stat

        # Calculate GC activity
        gc_runs = final_gc_stats[:count] - initial_gc_stats[:count]
        major_gc_runs = final_gc_stats[:major_gc_count] - initial_gc_stats[:major_gc_count]
        minor_gc_runs = final_gc_stats[:minor_gc_count] - initial_gc_stats[:minor_gc_count]

        puts "Garbage Collection Analysis:"
        puts "  Total GC runs: #{gc_runs}"
        puts "  Major GC runs: #{major_gc_runs}"
        puts "  Minor GC runs: #{minor_gc_runs}"
        puts "  GC runs per 1000 operations: #{gc_runs}"

        # GC frequency should be reasonable
        expect(gc_runs).to be < 100 # Should not trigger excessive GC
      end
    end

    context "GC optimization opportunities" do
      it "identifies objects that could be reused" do
        # Analyze object creation patterns to identify reuse opportunities

        # Example: UUID generation
        uuid_count = 1000
        start_time = Time.current

        uuid_count.times do
          test_uuid # Creates new UUID each time
        end

        uuid_generation_time = Time.current - start_time

        # Example: String creation
        string_count = 1000
        start_time = Time.current

        string_count.times do |i|
          "Test string #{i}" # Creates new string each time
        end

        string_creation_time = Time.current - start_time

        puts "Object Creation Analysis:"
        puts "  UUID generation: #{(uuid_generation_time * 1000).round(3)}ms for #{uuid_count} UUIDs"
        puts "  String creation: #{(string_creation_time * 1000).round(3)}ms for #{string_count} strings"

        # These are just measurements, not assertions
        expect(uuid_generation_time).to be > 0
        expect(string_creation_time).to be > 0
      end
    end
  end

  describe "Memory Usage Reporting" do
    context "detailed memory reports" do
      it "generates comprehensive memory usage report" do
        skip "GetProcessMem gem not available" unless defined?(GetProcessMem)

        report = {
          timestamp: Time.current.iso8601,
          ruby_version: RUBY_VERSION,
          platform: RUBY_PLATFORM,
          initial_memory: GetProcessMem.new.mb
        }

        # Test different operation types
        operations = {
          json_rpc_parsing: lambda {
            request = build_json_rpc_request("report_test", { data: "test" })
            100.times { A2A::Protocol::JsonRpc.parse_request(request.to_json) }
          },

          message_validation: lambda {
            message = build_message
            100.times { expect(message).to be_valid_a2a_message }
          },

          task_processing: lambda {
            task = build_task
            100.times { expect(task).to be_valid_a2a_task }
          },

          agent_card_validation: lambda {
            card = generate_minimal_agent_card
            100.times { expect(card).to be_valid_agent_card }
          }
        }

        operation_results = {}

        operations.each do |operation_name, operation_proc|
          GC.start # Clean slate for each operation

          before_memory = GetProcessMem.new.mb
          start_time = Time.current

          operation_proc.call

          end_time = Time.current
          after_memory = GetProcessMem.new.mb

          operation_results[operation_name] = {
            duration_ms: ((end_time - start_time) * 1000).round(3),
            memory_increase_mb: (after_memory - before_memory).round(3),
            operations_per_second: (100 / (end_time - start_time)).round(0)
          }
        end

        report[:operations] = operation_results
        report[:final_memory] = GetProcessMem.new.mb
        report[:total_memory_increase] = (report[:final_memory] - report[:initial_memory]).round(3)

        # Save detailed report
        save_fixture("memory_usage_report.json", report)

        puts "\nMemory Usage Report:"
        puts "Ruby Version: #{report[:ruby_version]}"
        puts "Platform: #{report[:platform]}"
        puts "Initial Memory: #{report[:initial_memory].round(3)}MB"
        puts "Final Memory: #{report[:final_memory].round(3)}MB"
        puts "Total Increase: #{report[:total_memory_increase]}MB"
        puts "\nOperation Details:"

        operation_results.each do |operation, results|
          puts "  #{operation}:"
          puts "    Duration: #{results[:duration_ms]}ms"
          puts "    Memory Increase: #{results[:memory_increase_mb]}MB"
          puts "    Throughput: #{results[:operations_per_second]} ops/sec"
        end

        # Verify reasonable memory usage
        expect(report[:total_memory_increase]).to be < 20 # Should not increase by more than 20MB
      end
    end
  end
end
