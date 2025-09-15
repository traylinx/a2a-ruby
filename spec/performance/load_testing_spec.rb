# frozen_string_literal: true

##
# Load Testing Suite for A2A Server Components
#
# This suite provides comprehensive load testing for A2A server components,
# including request handling, task management, and concurrent processing.
#
RSpec.describe "A2A Load Testing", :load_testing, :performance do
  # Load testing thresholds
  LOAD_THRESHOLDS = {
    requests_per_second: 100,        # Minimum RPS under load
    response_time_95th: 0.1,         # 95th percentile response time (100ms)
    error_rate: 0.01,                # Maximum 1% error rate
    concurrent_connections: 50, # Support 50 concurrent connections
    memory_growth_rate: 1.0,         # Max 1MB/minute memory growth
    cpu_utilization: 0.8             # Max 80% CPU utilization
  }.freeze

  describe "HTTP Request Load Testing" do
    context "single endpoint load" do
      it "handles sustained request load on JSON-RPC endpoint" do
        server = create_test_server
        server.start

        begin
          # Configure load test parameters
          duration = 30.seconds
          concurrent_clients = 10

          results = load_test(
            duration: duration,
            concurrent_requests: concurrent_clients
          ) do |client_id|
            # Simulate client making JSON-RPC request
            request = build_json_rpc_request("load_test", {
              client_id: client_id,
              timestamp: Time.current.to_f,
              data: "x" * 100 # 100 bytes payload
            })

            # Mock HTTP request to server
            start_time = Time.current

            begin
              # Simulate network delay
              sleep(0.001 + rand(0.004)) # 1-5ms simulated latency

              # Simulate processing
              parsed = A2A::Protocol::JsonRpc.parse_request(request.to_json)
              response = A2A::Protocol::JsonRpc.build_response(
                result: { processed: true, client_id: client_id },
                id: parsed.id
              )

              {
                success: true,
                response_time: Time.current - start_time,
                response_size: response.to_json.bytesize
              }
            rescue StandardError => e
              {
                success: false,
                error: e.message,
                response_time: Time.current - start_time
              }
            end
          end

          # Analyze results
          successful_requests = results[:results].count { |r| r[:success] }
          failed_requests = results[:results].count { |r| !r[:success] }
          error_rate = failed_requests.to_f / results[:total_requests]

          response_times = results[:results].select { |r| r[:success] }.pluck(:response_time)
          avg_response_time = response_times.sum / response_times.length
          p95_response_time = response_times.sort[(response_times.length * 0.95).to_i]

          puts "\nLoad Test Results (#{duration}s):"
          puts "  Total Requests: #{results[:total_requests]}"
          puts "  Successful: #{successful_requests}"
          puts "  Failed: #{failed_requests}"
          puts "  Error Rate: #{(error_rate * 100).round(2)}%"
          puts "  Requests/Second: #{results[:requests_per_second]}"
          puts "  Avg Response Time: #{(avg_response_time * 1000).round(2)}ms"
          puts "  95th Percentile: #{(p95_response_time * 1000).round(2)}ms"

          # Verify performance thresholds
          expect(results[:requests_per_second]).to be >= LOAD_THRESHOLDS[:requests_per_second]
          expect(error_rate).to be <= LOAD_THRESHOLDS[:error_rate]
          expect(p95_response_time).to be <= LOAD_THRESHOLDS[:response_time_95th]
        ensure
          server.stop
        end
      end

      it "handles burst traffic patterns" do
        server = create_test_server
        server.start

        begin
          # Simulate burst traffic: quiet periods followed by high load
          burst_results = []

          5.times do |burst_number|
            puts "Running burst #{burst_number + 1}/5..."

            # Quiet period
            sleep(2)

            # Burst period - high concurrent load for short duration
            burst_start = Time.current

            burst_result = run_concurrently(thread_count: 20) do |thread_id|
              requests_in_burst = 10
              thread_results = []

              requests_in_burst.times do |req_num|
                request = build_json_rpc_request("burst_test", {
                  burst: burst_number,
                  thread: thread_id,
                  request: req_num
                })

                start_time = Time.current

                begin
                  parsed = A2A::Protocol::JsonRpc.parse_request(request.to_json)
                  A2A::Protocol::JsonRpc.build_response(
                    result: { processed: true },
                    id: parsed.id
                  )

                  thread_results << {
                    success: true,
                    response_time: Time.current - start_time
                  }
                rescue StandardError => e
                  thread_results << {
                    success: false,
                    error: e.message,
                    response_time: Time.current - start_time
                  }
                end
              end

              thread_results
            end

            burst_duration = Time.current - burst_start
            all_requests = burst_result.flatten
            successful = all_requests.count { |r| r[:success] }

            burst_results << {
              burst_number: burst_number + 1,
              duration: burst_duration,
              total_requests: all_requests.length,
              successful_requests: successful,
              requests_per_second: all_requests.length / burst_duration,
              avg_response_time: all_requests.sum { |r| r[:response_time] } / all_requests.length
            }
          end

          puts "\nBurst Test Results:"
          burst_results.each do |result|
            puts "  Burst #{result[:burst_number]}:"
            puts "    Duration: #{result[:duration].round(3)}s"
            puts "    Requests: #{result[:total_requests]}"
            puts "    Success Rate: #{(result[:successful_requests].to_f / result[:total_requests] * 100).round(1)}%"
            puts "    RPS: #{result[:requests_per_second].round(0)}"
            puts "    Avg Response: #{(result[:avg_response_time] * 1000).round(2)}ms"

            # All bursts should handle the load successfully
            success_rate = result[:successful_requests].to_f / result[:total_requests]
            expect(success_rate).to be >= 0.95 # 95% success rate minimum
            expect(result[:requests_per_second]).to be >= 50 # Minimum RPS during burst
          end
        ensure
          server.stop
        end
      end
    end

    context "multiple endpoint load" do
      it "handles load across different A2A methods" do
        server = create_test_server
        server.start

        begin
          # Define different A2A methods to test
          methods_to_test = [
            {
              method: "message/send",
              params: -> { { message: build_message } },
              weight: 0.4 # 40% of requests
            },
            {
              method: "tasks/get",
              params: -> { { id: test_uuid } },
              weight: 0.3 # 30% of requests
            },
            {
              method: "agent/getCard",
              params: -> { {} },
              weight: 0.2 # 20% of requests
            },
            {
              method: "tasks/cancel",
              params: -> { { id: test_uuid } },
              weight: 0.1 # 10% of requests
            }
          ]

          # Run mixed load test
          duration = 20.seconds
          results = load_test(
            duration: duration,
            concurrent_requests: 8
          ) do |_client_id|
            # Select method based on weights
            rand_value = rand
            cumulative_weight = 0
            selected_method = nil

            methods_to_test.each do |method_config|
              cumulative_weight += method_config[:weight]
              if rand_value <= cumulative_weight
                selected_method = method_config
                break
              end
            end

            request = build_json_rpc_request(
              selected_method[:method],
              selected_method[:params].call
            )

            start_time = Time.current

            begin
              parsed = A2A::Protocol::JsonRpc.parse_request(request.to_json)

              # Simulate different processing times for different methods
              processing_delay = case parsed.method
                                 when "message/send" then 0.005 # 5ms
                                 when "tasks/get" then 0.002 # 2ms
                                 when "agent/getCard" then 0.001 # 1ms
                                 when "tasks/cancel" then 0.003 # 3ms
                                 else 0.001
                                 end

              sleep(processing_delay)

              A2A::Protocol::JsonRpc.build_response(
                result: { method: parsed.method, processed: true },
                id: parsed.id
              )

              {
                success: true,
                method: parsed.method,
                response_time: Time.current - start_time
              }
            rescue StandardError => e
              {
                success: false,
                method: selected_method[:method],
                error: e.message,
                response_time: Time.current - start_time
              }
            end
          end

          # Analyze results by method
          method_stats = {}
          results[:results].each do |result|
            method = result[:method]
            method_stats[method] ||= { total: 0, successful: 0, response_times: [] }
            method_stats[method][:total] += 1
            method_stats[method][:successful] += 1 if result[:success]
            method_stats[method][:response_times] << result[:response_time] if result[:success]
          end

          puts "\nMixed Load Test Results:"
          puts "  Total Duration: #{duration}s"
          puts "  Overall RPS: #{results[:requests_per_second].round(0)}"
          puts "\nPer-Method Statistics:"

          method_stats.each do |method, stats|
            success_rate = stats[:successful].to_f / stats[:total]
            avg_response_time = stats[:response_times].sum / stats[:response_times].length

            puts "  #{method}:"
            puts "    Requests: #{stats[:total]}"
            puts "    Success Rate: #{(success_rate * 100).round(1)}%"
            puts "    Avg Response: #{(avg_response_time * 1000).round(2)}ms"

            # Each method should perform well
            expect(success_rate).to be >= 0.95
            expect(avg_response_time).to be <= 0.05 # 50ms max
          end
        ensure
          server.stop
        end
      end
    end
  end

  describe "Task Management Load Testing" do
    context "concurrent task operations" do
      it "handles concurrent task creation and updates" do
        task_manager = mock_task_manager

        # Simulate concurrent task operations
        duration = 15.seconds
        start_time = Time.current

        results = run_concurrently(thread_count: 10) do |thread_id|
          thread_results = []

          while (Time.current - start_time) < duration
            operation_start = Time.current

            begin
              # Create task
              task = task_manager.create_task(
                type: "load_test_task",
                thread_id: thread_id,
                timestamp: Time.current.to_f
              )

              # Update task status multiple times
              statuses = %w[working completed]
              statuses.each do |status|
                task_manager.update_task_status(task[:id], { state: status })
              end

              # Get task
              task_manager.get_task(task[:id])

              thread_results << {
                success: true,
                operations: 4, # create + 2 updates + get
                duration: Time.current - operation_start
              }
            rescue StandardError => e
              thread_results << {
                success: false,
                error: e.message,
                duration: Time.current - operation_start
              }
            end

            # Small delay to prevent overwhelming
            sleep(0.001)
          end

          thread_results
        end

        all_results = results.flatten
        successful_ops = all_results.count { |r| r[:success] }
        total_operations = all_results.sum { |r| r[:operations] || 0 }

        puts "\nTask Management Load Test:"
        puts "  Duration: #{duration}s"
        puts "  Total Operation Sets: #{all_results.length}"
        puts "  Successful Sets: #{successful_ops}"
        puts "  Total Operations: #{total_operations}"
        puts "  Operations/Second: #{(total_operations / duration).round(0)}"
        puts "  Success Rate: #{(successful_ops.to_f / all_results.length * 100).round(1)}%"

        # Verify performance
        success_rate = successful_ops.to_f / all_results.length
        ops_per_second = total_operations / duration

        expect(success_rate).to be >= 0.95
        expect(ops_per_second).to be >= 100 # Should handle 100+ operations/second
      end

      it "handles task lifecycle under load" do
        task_manager = mock_task_manager

        # Create many tasks and manage their full lifecycle
        task_count = 1000
        tasks_created = []

        # Phase 1: Create all tasks
        creation_time = measure_time do
          run_concurrently(thread_count: 10) do |thread_id|
            (task_count / 10).times do |i|
              task = task_manager.create_task(
                type: "lifecycle_test",
                thread_id: thread_id,
                index: i
              )
              tasks_created << task[:id]
            end
          end
        end

        # Phase 2: Update all tasks through lifecycle
        update_time = measure_time do
          run_concurrently(thread_count: 10) do |thread_id|
            start_idx = thread_id * (task_count / 10)
            end_idx = start_idx + (task_count / 10)

            tasks_created[start_idx...end_idx].each do |task_id|
              # Simulate task progression
              %w[working completed].each do |state|
                task_manager.update_task_status(task_id, { state: state })
              end
            end
          end
        end

        # Phase 3: Retrieve all tasks
        retrieval_time = measure_time do
          run_concurrently(thread_count: 10) do |thread_id|
            start_idx = thread_id * (task_count / 10)
            end_idx = start_idx + (task_count / 10)

            tasks_created[start_idx...end_idx].each do |task_id|
              task_manager.get_task(task_id)
            end
          end
        end

        puts "\nTask Lifecycle Load Test (#{task_count} tasks):"
        puts "  Creation Time: #{(creation_time[:duration] * 1000).round(0)}ms"
        puts "  Update Time: #{(update_time[:duration] * 1000).round(0)}ms"
        puts "  Retrieval Time: #{(retrieval_time[:duration] * 1000).round(0)}ms"
        puts "  Creation Rate: #{(task_count / creation_time[:duration]).round(0)} tasks/sec"
        puts "  Update Rate: #{(task_count * 2 / update_time[:duration]).round(0)} updates/sec"
        puts "  Retrieval Rate: #{(task_count / retrieval_time[:duration]).round(0)} retrievals/sec"

        # Verify performance thresholds
        expect(creation_time[:duration]).to be < 10 # 10 seconds max for 1000 tasks
        expect(update_time[:duration]).to be < 20 # 20 seconds max for 2000 updates
        expect(retrieval_time[:duration]).to be < 5 # 5 seconds max for 1000 retrievals
      end
    end
  end

  describe "Memory and Resource Load Testing" do
    context "memory usage under load" do
      it "maintains stable memory usage during sustained load" do
        skip "GetProcessMem gem not available" unless defined?(GetProcessMem)

        initial_memory = GetProcessMem.new.mb
        memory_samples = []

        # Run sustained load for 60 seconds, sampling memory every 5 seconds
        duration = 60.seconds
        sample_interval = 5.seconds
        start_time = Time.current
        last_sample_time = start_time

        operations_count = 0

        while (Time.current - start_time) < duration
          # Perform operations
          100.times do
            request = build_json_rpc_request("memory_load_test", {
              timestamp: Time.current.to_f,
              data: "x" * 500 # 500 bytes per request
            })

            A2A::Protocol::JsonRpc.parse_request(request.to_json)

            message = build_message(text: "Memory load test #{operations_count}")
            expect(message).to be_valid_a2a_message

            operations_count += 1
          end

          # Sample memory if interval has passed
          if (Time.current - last_sample_time) >= sample_interval
            current_memory = GetProcessMem.new.mb
            memory_samples << {
              time: Time.current - start_time,
              memory_mb: current_memory,
              operations: operations_count
            }
            last_sample_time = Time.current

            puts "Memory sample at #{(Time.current - start_time).round(0)}s: #{current_memory.round(1)}MB (#{operations_count} ops)"
          end

          # Small delay to prevent CPU saturation
          sleep(0.001)
        end

        final_memory = GetProcessMem.new.mb
        total_memory_increase = final_memory - initial_memory

        # Calculate memory growth rate
        if memory_samples.length >= 2
          time_span = memory_samples.last[:time] - memory_samples.first[:time]
          memory_growth = memory_samples.last[:memory_mb] - memory_samples.first[:memory_mb]
          growth_rate_per_minute = (memory_growth / time_span) * 60

          puts "\nMemory Load Test Results:"
          puts "  Duration: #{duration}s"
          puts "  Total Operations: #{operations_count}"
          puts "  Operations/Second: #{(operations_count / duration).round(0)}"
          puts "  Initial Memory: #{initial_memory.round(1)}MB"
          puts "  Final Memory: #{final_memory.round(1)}MB"
          puts "  Total Increase: #{total_memory_increase.round(1)}MB"
          puts "  Growth Rate: #{growth_rate_per_minute.round(3)}MB/minute"

          # Verify memory growth is within acceptable limits
          expect(growth_rate_per_minute).to be <= LOAD_THRESHOLDS[:memory_growth_rate]
          expect(total_memory_increase).to be <= 30 # Max 30MB increase over test
        end
      end
    end

    context "resource cleanup under load" do
      it "properly cleans up resources during high-throughput operations" do
        # Track object creation and cleanup
        initial_object_count = ObjectSpace.count_objects if defined?(ObjectSpace)

        # Perform high-throughput operations
        operations = 5000

        result = measure_time do
          run_concurrently(thread_count: 5) do |thread_id|
            (operations / 5).times do |i|
              # Create temporary objects
              request = build_json_rpc_request("cleanup_test_#{thread_id}_#{i}", {
                thread_id: thread_id,
                operation_id: i,
                payload: "x" * 200
              })

              parsed = A2A::Protocol::JsonRpc.parse_request(request.to_json)

              A2A::Protocol::JsonRpc.build_response(
                result: { processed: true, thread_id: thread_id },
                id: parsed.id
              )

              # Create temporary message
              message = build_message(text: "Cleanup test #{thread_id}-#{i}")
              expect(message).to be_valid_a2a_message
            end
          end
        end

        # Force garbage collection
        3.times { GC.start }

        final_object_count = ObjectSpace.count_objects if defined?(ObjectSpace)

        puts "\nResource Cleanup Test:"
        puts "  Operations: #{operations}"
        puts "  Duration: #{(result[:duration] * 1000).round(0)}ms"
        puts "  Throughput: #{(operations / result[:duration]).round(0)} ops/sec"

        if initial_object_count && final_object_count
          object_increase = final_object_count.values.sum - initial_object_count.values.sum
          puts "  Object Count Increase: #{object_increase}"

          # Object count should not increase excessively
          expect(object_increase).to be < operations # Should be less than 1 object per operation
        end

        # Performance should be maintained
        expect(result[:duration]).to be < 30 # Should complete in under 30 seconds
      end
    end
  end

  describe "Stress Testing" do
    context "extreme load conditions" do
      it "handles extreme concurrent load" do
        # Test with very high concurrency
        extreme_concurrency = 50
        operations_per_thread = 100

        puts "\nRunning extreme load test (#{extreme_concurrency} threads, #{operations_per_thread} ops each)..."

        result = measure_time do
          results = run_concurrently(thread_count: extreme_concurrency) do |thread_id|
            thread_results = []

            operations_per_thread.times do |op_id|
              op_start = Time.current

              begin
                request = build_json_rpc_request("extreme_load_#{thread_id}_#{op_id}", {
                  thread_id: thread_id,
                  operation_id: op_id,
                  timestamp: Time.current.to_f
                })

                A2A::Protocol::JsonRpc.parse_request(request.to_json)

                thread_results << {
                  success: true,
                  duration: Time.current - op_start
                }
              rescue StandardError => e
                thread_results << {
                  success: false,
                  error: e.message,
                  duration: Time.current - op_start
                }
              end
            end

            thread_results
          end

          results.flatten
        end

        total_operations = extreme_concurrency * operations_per_thread
        successful_operations = result[:result].count { |r| r[:success] }
        success_rate = successful_operations.to_f / total_operations

        puts "Extreme Load Test Results:"
        puts "  Total Operations: #{total_operations}"
        puts "  Successful: #{successful_operations}"
        puts "  Success Rate: #{(success_rate * 100).round(1)}%"
        puts "  Duration: #{(result[:duration] * 1000).round(0)}ms"
        puts "  Throughput: #{(total_operations / result[:duration]).round(0)} ops/sec"

        # Should maintain reasonable performance even under extreme load
        expect(success_rate).to be >= 0.90 # 90% success rate minimum under extreme load
        expect(result[:duration]).to be < 60 # Should complete within 60 seconds
      end

      it "recovers gracefully from resource exhaustion" do
        # Simulate resource exhaustion and recovery
        puts "\nTesting resource exhaustion recovery..."

        # Phase 1: Normal load
        normal_load_result = measure_time do
          100.times do |i|
            request = build_json_rpc_request("normal_#{i}", { data: "x" * 100 })
            A2A::Protocol::JsonRpc.parse_request(request.to_json)
          end
        end

        # Phase 2: Extreme load to exhaust resources
        exhaustion_errors = 0
        measure_time do
          1000.times do |i|
            request = build_json_rpc_request("exhaustion_#{i}", {
              data: "x" * 10_000 # 10KB per request
            })
            A2A::Protocol::JsonRpc.parse_request(request.to_json)
          end
        rescue StandardError
          exhaustion_errors += 1
        end

        # Phase 3: Recovery - return to normal load
        GC.start # Force cleanup

        recovery_result = measure_time do
          100.times do |i|
            request = build_json_rpc_request("recovery_#{i}", { data: "x" * 100 })
            A2A::Protocol::JsonRpc.parse_request(request.to_json)
          end
        end

        puts "Resource Exhaustion Recovery Test:"
        puts "  Normal Load Time: #{(normal_load_result[:duration] * 1000).round(0)}ms"
        puts "  Exhaustion Errors: #{exhaustion_errors}"
        puts "  Recovery Time: #{(recovery_result[:duration] * 1000).round(0)}ms"
        puts "  Performance Recovery: #{((normal_load_result[:duration] / recovery_result[:duration]) * 100).round(0)}%"

        # Should recover to near-normal performance
        performance_ratio = recovery_result[:duration] / normal_load_result[:duration]
        expect(performance_ratio).to be <= 2.0 # Recovery should be within 2x of normal performance
      end
    end
  end

  describe "Performance Regression Detection" do
    context "load test baselines" do
      it "establishes load testing baselines" do
        baselines = {}

        # JSON-RPC throughput baseline
        result = measure_time do
          1000.times do |i|
            request = build_json_rpc_request("baseline_#{i}", { index: i })
            A2A::Protocol::JsonRpc.parse_request(request.to_json)
          end
        end
        baselines[:json_rpc_throughput] = 1000 / result[:duration]

        # Concurrent processing baseline
        result = measure_time do
          run_concurrently(thread_count: 10) do |thread_id|
            100.times do |i|
              request = build_json_rpc_request("concurrent_#{thread_id}_#{i}", {
                thread_id: thread_id,
                index: i
              })
              A2A::Protocol::JsonRpc.parse_request(request.to_json)
            end
          end
        end
        baselines[:concurrent_throughput] = 1000 / result[:duration]

        # Memory efficiency baseline
        if defined?(GetProcessMem)
          initial_memory = GetProcessMem.new.mb

          1000.times do |i|
            request = build_json_rpc_request("memory_baseline_#{i}", {
              data: "x" * 500
            })
            A2A::Protocol::JsonRpc.parse_request(request.to_json)
          end

          GC.start
          final_memory = GetProcessMem.new.mb
          baselines[:memory_per_1000_ops] = final_memory - initial_memory
        end

        # Save baselines
        baseline_data = {
          timestamp: Time.current.iso8601,
          ruby_version: RUBY_VERSION,
          platform: RUBY_PLATFORM,
          baselines: baselines
        }

        save_fixture("load_test_baselines.json", baseline_data)

        puts "\nLoad Testing Baselines:"
        baselines.each do |metric, value|
          case metric
          when :json_rpc_throughput, :concurrent_throughput
            puts "  #{metric}: #{value.round(0)} ops/sec"
          when :memory_per_1000_ops
            puts "  #{metric}: #{value.round(3)} MB"
          else
            puts "  #{metric}: #{value}"
          end
        end

        # Verify baselines meet minimum requirements
        expect(baselines[:json_rpc_throughput]).to be >= LOAD_THRESHOLDS[:requests_per_second]
        expect(baselines[:concurrent_throughput]).to be >= LOAD_THRESHOLDS[:requests_per_second]
      end
    end
  end
end
