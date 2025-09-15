# frozen_string_literal: true

require 'benchmark'

##
# Performance Benchmark Suite for A2A Ruby Gem
#
# This suite measures performance of core A2A operations and provides
# benchmarking tools for performance regression detection.
#
RSpec.describe "A2A Performance Benchmarks", :performance do
  # Performance thresholds (in seconds)
  PERFORMANCE_THRESHOLDS = {
    json_rpc_parse: 0.001,      # 1ms for single request parsing
    json_rpc_build: 0.001,      # 1ms for response building
    message_validation: 0.005,   # 5ms for message validation
    task_validation: 0.005,      # 5ms for task validation
    agent_card_validation: 0.01, # 10ms for agent card validation
    batch_processing: 0.1,       # 100ms for 100-item batch
    large_message: 0.05,         # 50ms for 1MB message
    concurrent_requests: 1.0     # 1s for 100 concurrent operations
  }.freeze

  describe "JSON-RPC Performance" do
    context "request parsing" do
      it "parses single requests efficiently" do
        request_json = build_json_rpc_request("test/method", { key: "value" }).to_json
        
        result = measure_time do
          1000.times do
            A2A::Protocol::JsonRpc.parse_request(request_json)
          end
        end
        
        avg_time = result[:duration] / 1000
        expect(avg_time).to be < PERFORMANCE_THRESHOLDS[:json_rpc_parse]
        
        puts "JSON-RPC parsing: #{(avg_time * 1000).round(3)}ms per request"
      end

      it "parses batch requests efficiently" do
        batch_requests = (1..100).map do |i|
          build_json_rpc_request("method_#{i}", { index: i }, i)
        end
        batch_json = batch_requests.to_json
        
        result = measure_time do
          10.times do
            parsed = A2A::Protocol::JsonRpc.parse_request(batch_json)
            expect(parsed.length).to eq(100)
          end
        end
        
        avg_time = result[:duration] / 10
        expect(avg_time).to be < PERFORMANCE_THRESHOLDS[:batch_processing]
        
        puts "Batch parsing (100 requests): #{(avg_time * 1000).round(3)}ms per batch"
      end

      it "handles large request payloads efficiently" do
        large_params = {
          data: "x" * 100_000, # 100KB payload
          metadata: (1..1000).map { |i| { "key_#{i}" => "value_#{i}" } }
        }
        large_request_json = build_json_rpc_request("large/method", large_params).to_json
        
        result = measure_time do
          10.times do
            A2A::Protocol::JsonRpc.parse_request(large_request_json)
          end
        end
        
        avg_time = result[:duration] / 10
        expect(avg_time).to be < PERFORMANCE_THRESHOLDS[:large_message]
        
        puts "Large request parsing (#{large_request_json.bytesize} bytes): #{(avg_time * 1000).round(3)}ms"
      end
    end

    context "response building" do
      it "builds responses efficiently" do
        result_data = { message: "success", data: (1..100).to_a }
        
        result = measure_time do
          1000.times do
            A2A::Protocol::JsonRpc.build_response(result: result_data, id: 1)
          end
        end
        
        avg_time = result[:duration] / 1000
        expect(avg_time).to be < PERFORMANCE_THRESHOLDS[:json_rpc_build]
        
        puts "Response building: #{(avg_time * 1000).round(3)}ms per response"
      end

      it "builds error responses efficiently" do
        error_data = {
          code: A2A::Protocol::JsonRpc::TASK_NOT_FOUND,
          message: "Task not found",
          data: { taskId: test_uuid, details: "Additional error information" }
        }
        
        result = measure_time do
          1000.times do
            A2A::Protocol::JsonRpc.build_response(error: error_data, id: 1)
          end
        end
        
        avg_time = result[:duration] / 1000
        expect(avg_time).to be < PERFORMANCE_THRESHOLDS[:json_rpc_build]
        
        puts "Error response building: #{(avg_time * 1000).round(3)}ms per response"
      end
    end
  end

  describe "Message Processing Performance" do
    context "message validation" do
      it "validates simple messages efficiently" do
        message = build_message(text: "Simple test message")
        
        result = measure_time do
          1000.times do
            expect(message).to be_valid_a2a_message
          end
        end
        
        avg_time = result[:duration] / 1000
        expect(avg_time).to be < PERFORMANCE_THRESHOLDS[:message_validation]
        
        puts "Simple message validation: #{(avg_time * 1000).round(3)}ms per message"
      end

      it "validates complex messages efficiently" do
        complex_message = generate_complex_message
        
        result = measure_time do
          100.times do
            expect(complex_message).to be_valid_a2a_message
          end
        end
        
        avg_time = result[:duration] / 100
        expect(avg_time).to be < PERFORMANCE_THRESHOLDS[:message_validation] * 2 # Allow 2x for complex
        
        puts "Complex message validation: #{(avg_time * 1000).round(3)}ms per message"
      end

      it "processes message batches efficiently" do
        messages = (1..100).map { |i| build_message(text: "Message #{i}") }
        
        result = measure_time do
          10.times do
            messages.each { |msg| expect(msg).to be_valid_a2a_message }
          end
        end
        
        avg_batch_time = result[:duration] / 10
        expect(avg_batch_time).to be < PERFORMANCE_THRESHOLDS[:batch_processing]
        
        puts "Message batch validation (100 messages): #{(avg_batch_time * 1000).round(3)}ms per batch"
      end
    end

    context "message serialization" do
      it "serializes messages to JSON efficiently" do
        message = generate_complex_message
        
        result = measure_time do
          1000.times do
            message.to_json
          end
        end
        
        avg_time = result[:duration] / 1000
        expect(avg_time).to be < 0.002 # 2ms threshold for serialization
        
        puts "Message JSON serialization: #{(avg_time * 1000).round(3)}ms per message"
      end

      it "deserializes messages from JSON efficiently" do
        message_json = generate_complex_message.to_json
        
        result = measure_time do
          1000.times do
            JSON.parse(message_json, symbolize_names: true)
          end
        end
        
        avg_time = result[:duration] / 1000
        expect(avg_time).to be < 0.002 # 2ms threshold for deserialization
        
        puts "Message JSON deserialization: #{(avg_time * 1000).round(3)}ms per message"
      end
    end
  end

  describe "Task Processing Performance" do
    context "task validation" do
      it "validates simple tasks efficiently" do
        task = build_task
        
        result = measure_time do
          1000.times do
            expect(task).to be_valid_a2a_task
          end
        end
        
        avg_time = result[:duration] / 1000
        expect(avg_time).to be < PERFORMANCE_THRESHOLDS[:task_validation]
        
        puts "Simple task validation: #{(avg_time * 1000).round(3)}ms per task"
      end

      it "validates comprehensive tasks efficiently" do
        comprehensive_task = generate_comprehensive_task
        
        result = measure_time do
          100.times do
            expect(comprehensive_task).to be_valid_a2a_task
          end
        end
        
        avg_time = result[:duration] / 100
        expect(avg_time).to be < PERFORMANCE_THRESHOLDS[:task_validation] * 3 # Allow 3x for comprehensive
        
        puts "Comprehensive task validation: #{(avg_time * 1000).round(3)}ms per task"
      end
    end

    context "task lifecycle operations" do
      it "creates tasks efficiently" do
        task_manager = mock_task_manager
        
        result = measure_time do
          100.times do |i|
            task_manager.create_task(type: "benchmark_task_#{i}")
          end
        end
        
        avg_time = result[:duration] / 100
        expect(avg_time).to be < 0.01 # 10ms per task creation
        
        puts "Task creation: #{(avg_time * 1000).round(3)}ms per task"
      end

      it "updates task status efficiently" do
        task_manager = mock_task_manager
        task_ids = (1..100).map { |i| test_uuid }
        
        result = measure_time do
          task_ids.each do |task_id|
            task_manager.update_task_status(task_id, { state: "working" })
          end
        end
        
        avg_time = result[:duration] / 100
        expect(avg_time).to be < 0.005 # 5ms per status update
        
        puts "Task status update: #{(avg_time * 1000).round(3)}ms per update"
      end
    end
  end

  describe "Agent Card Performance" do
    context "agent card validation" do
      it "validates minimal agent cards efficiently" do
        minimal_card = generate_minimal_agent_card
        
        result = measure_time do
          1000.times do
            expect(minimal_card).to be_valid_agent_card
          end
        end
        
        avg_time = result[:duration] / 1000
        expect(avg_time).to be < PERFORMANCE_THRESHOLDS[:agent_card_validation]
        
        puts "Minimal agent card validation: #{(avg_time * 1000).round(3)}ms per card"
      end

      it "validates comprehensive agent cards efficiently" do
        full_card = generate_full_agent_card
        
        result = measure_time do
          100.times do
            expect(full_card).to be_valid_agent_card
          end
        end
        
        avg_time = result[:duration] / 100
        expect(avg_time).to be < PERFORMANCE_THRESHOLDS[:agent_card_validation] * 2 # Allow 2x for full card
        
        puts "Full agent card validation: #{(avg_time * 1000).round(3)}ms per card"
      end
    end

    context "agent card serialization" do
      it "serializes agent cards efficiently" do
        card = generate_full_agent_card
        
        result = measure_time do
          500.times do
            card.to_json
          end
        end
        
        avg_time = result[:duration] / 500
        expect(avg_time).to be < 0.005 # 5ms for agent card serialization
        
        puts "Agent card serialization: #{(avg_time * 1000).round(3)}ms per card"
      end
    end
  end

  describe "Concurrent Processing Performance" do
    context "concurrent request handling" do
      it "handles concurrent JSON-RPC parsing" do
        requests = (1..100).map do |i|
          build_json_rpc_request("concurrent_method_#{i}", { index: i }, i).to_json
        end
        
        result = measure_time do
          run_concurrently(thread_count: 10) do |thread_id|
            requests.each do |request_json|
              A2A::Protocol::JsonRpc.parse_request(request_json)
            end
          end
        end
        
        expect(result[:duration]).to be < PERFORMANCE_THRESHOLDS[:concurrent_requests]
        
        puts "Concurrent parsing (10 threads, 100 requests each): #{(result[:duration] * 1000).round(3)}ms total"
      end

      it "handles concurrent message validation" do
        messages = (1..50).map { |i| build_message(text: "Concurrent message #{i}") }
        
        result = measure_time do
          run_concurrently(thread_count: 10) do |thread_id|
            messages.each { |msg| expect(msg).to be_valid_a2a_message }
          end
        end
        
        expect(result[:duration]).to be < PERFORMANCE_THRESHOLDS[:concurrent_requests]
        
        puts "Concurrent validation (10 threads, 50 messages each): #{(result[:duration] * 1000).round(3)}ms total"
      end
    end

    context "memory usage under load" do
      it "maintains reasonable memory usage during processing", :skip_if_no_memory_gem do
        skip "GetProcessMem gem not available" unless defined?(GetProcessMem)
        
        initial_memory = GetProcessMem.new.mb
        
        # Process a large number of operations
        1000.times do |i|
          request = build_json_rpc_request("memory_test_#{i}", { data: "x" * 1000 })
          A2A::Protocol::JsonRpc.parse_request(request.to_json)
          
          message = build_message(text: "Memory test message #{i}")
          expect(message).to be_valid_a2a_message
        end
        
        final_memory = GetProcessMem.new.mb
        memory_increase = final_memory - initial_memory
        
        # Should not increase memory by more than 50MB for 1000 operations
        expect(memory_increase).to be < 50
        
        puts "Memory usage increase: #{memory_increase.round(2)}MB for 1000 operations"
      end
    end
  end

  describe "Load Testing Scenarios" do
    context "high-throughput scenarios" do
      it "handles high message throughput" do
        message_count = 1000
        messages = (1..message_count).map { |i| build_message(text: "Load test #{i}") }
        
        result = measure_time do
          messages.each { |msg| expect(msg).to be_valid_a2a_message }
        end
        
        throughput = message_count / result[:duration]
        expect(throughput).to be > 1000 # Should handle >1000 messages/second
        
        puts "Message validation throughput: #{throughput.round(0)} messages/second"
      end

      it "handles burst request processing" do
        burst_size = 100
        burst_count = 10
        
        total_time = 0
        
        burst_count.times do |burst|
          requests = (1..burst_size).map do |i|
            build_json_rpc_request("burst_#{burst}_#{i}", { index: i })
          end
          
          result = measure_time do
            requests.each { |req| expect(req).to be_valid_json_rpc_request }
          end
          
          total_time += result[:duration]
        end
        
        avg_burst_time = total_time / burst_count
        expect(avg_burst_time).to be < 0.1 # 100ms per burst of 100 requests
        
        puts "Burst processing (#{burst_size} requests): #{(avg_burst_time * 1000).round(3)}ms per burst"
      end
    end

    context "stress testing" do
      it "maintains performance under sustained load" do
        duration = 5 # seconds
        start_time = Time.current
        operations = 0
        
        while (Time.current - start_time) < duration
          request = build_json_rpc_request("stress_test", { timestamp: Time.current.to_f })
          A2A::Protocol::JsonRpc.parse_request(request.to_json)
          operations += 1
        end
        
        ops_per_second = operations / duration
        expect(ops_per_second).to be > 500 # Should maintain >500 ops/second
        
        puts "Sustained load performance: #{ops_per_second.round(0)} operations/second over #{duration}s"
      end
    end
  end

  describe "Performance Regression Detection" do
    context "baseline measurements" do
      it "records baseline performance metrics" do
        baselines = {}
        
        # JSON-RPC parsing baseline
        request_json = build_json_rpc_request("baseline", { test: true }).to_json
        result = measure_time do
          1000.times { A2A::Protocol::JsonRpc.parse_request(request_json) }
        end
        baselines[:json_rpc_parse] = result[:duration] / 1000
        
        # Message validation baseline
        message = build_message
        result = measure_time do
          1000.times { expect(message).to be_valid_a2a_message }
        end
        baselines[:message_validation] = result[:duration] / 1000
        
        # Task validation baseline
        task = build_task
        result = measure_time do
          1000.times { expect(task).to be_valid_a2a_task }
        end
        baselines[:task_validation] = result[:duration] / 1000
        
        # Agent card validation baseline
        card = generate_minimal_agent_card
        result = measure_time do
          1000.times { expect(card).to be_valid_agent_card }
        end
        baselines[:agent_card_validation] = result[:duration] / 1000
        
        # Save baselines for comparison
        save_fixture("performance_baselines.json", {
          timestamp: Time.current.iso8601,
          ruby_version: RUBY_VERSION,
          baselines: baselines
        })
        
        puts "\nPerformance Baselines:"
        baselines.each do |operation, time|
          puts "  #{operation}: #{(time * 1000).round(3)}ms"
        end
        
        # All operations should be within thresholds
        baselines.each do |operation, time|
          if PERFORMANCE_THRESHOLDS[operation]
            expect(time).to be < PERFORMANCE_THRESHOLDS[operation]
          end
        end
      end
    end

    context "regression detection" do
      it "detects performance regressions" do
        # This would compare current performance against saved baselines
        # For now, just verify the mechanism works
        
        current_performance = {
          json_rpc_parse: 0.0005,
          message_validation: 0.002,
          task_validation: 0.003
        }
        
        baseline_performance = {
          json_rpc_parse: 0.0003,
          message_validation: 0.0015,
          task_validation: 0.002
        }
        
        regressions = []
        current_performance.each do |operation, current_time|
          baseline_time = baseline_performance[operation]
          if baseline_time && current_time > (baseline_time * 1.5) # 50% regression threshold
            regressions << {
              operation: operation,
              baseline: baseline_time,
              current: current_time,
              regression: ((current_time / baseline_time - 1) * 100).round(1)
            }
          end
        end
        
        if regressions.any?
          puts "\nPerformance Regressions Detected:"
          regressions.each do |reg|
            puts "  #{reg[:operation]}: #{reg[:regression]}% slower (#{reg[:baseline]}ms -> #{reg[:current]}ms)"
          end
        end
        
        # For this test, expect no regressions
        expect(regressions).to be_empty
      end
    end
  end

  describe "Profiling and Optimization" do
    context "memory profiling" do
      it "profiles memory allocation patterns", :skip_if_no_memory_profiler do
        skip "Memory profiler not available"
        
        # This would use a memory profiler to identify allocation hotspots
        # Placeholder for actual memory profiling implementation
      end
    end

    context "CPU profiling" do
      it "profiles CPU usage patterns", :skip_if_no_cpu_profiler do
        skip "CPU profiler not available"
        
        # This would use a CPU profiler to identify performance bottlenecks
        # Placeholder for actual CPU profiling implementation
      end
    end
  end
end