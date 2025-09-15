# frozen_string_literal: true

##
# Performance Regression Detection Suite
#
# This suite provides automated performance regression detection by comparing
# current performance metrics against historical baselines and detecting
# significant performance degradations.
#
RSpec.describe "Performance Regression Detection", :performance, :regression do
  # Regression thresholds (percentage increase that triggers alert)
  REGRESSION_THRESHOLDS = {
    response_time: 0.25,        # 25% increase in response time
    throughput: 0.20,           # 20% decrease in throughput
    memory_usage: 0.30,         # 30% increase in memory usage
    error_rate: 0.05,           # 5% increase in error rate
    cpu_usage: 0.25,            # 25% increase in CPU usage
    gc_frequency: 0.40          # 40% increase in GC frequency
  }.freeze

  describe "Baseline Management" do
    context "baseline creation" do
      it "creates comprehensive performance baselines" do
        baselines = {}
        
        # Response time baselines
        operations = {
          json_rpc_parse: -> {
            request = build_json_rpc_request("baseline", { test: true })
            A2A::Protocol::JsonRpc.parse_request(request.to_json)
          },
          
          json_rpc_build: -> {
            A2A::Protocol::JsonRpc.build_response(result: { test: true }, id: 1)
          },
          
          message_validation: -> {
            message = build_message
            expect(message).to be_valid_a2a_message
          },
          
          task_validation: -> {
            task = build_task
            expect(task).to be_valid_a2a_task
          },
          
          agent_card_validation: -> {
            card = generate_minimal_agent_card
            expect(card).to be_valid_agent_card
          }
        }
        
        operations.each do |operation_name, operation_proc|
          # Warm up
          10.times { operation_proc.call }
          
          # Measure response time
          times = []
          100.times do
            result = measure_time { operation_proc.call }
            times << result[:duration]
          end
          
          baselines[operation_name] = {
            avg_response_time: times.sum / times.length,
            min_response_time: times.min,
            max_response_time: times.max,
            p95_response_time: times.sort[(times.length * 0.95).to_i],
            p99_response_time: times.sort[(times.length * 0.99).to_i]
          }
        end
        
        # Throughput baselines
        throughput_tests = {
          json_rpc_throughput: -> {
            request = build_json_rpc_request("throughput", { test: true })
            request_json = request.to_json
            
            result = measure_time do
              1000.times { A2A::Protocol::JsonRpc.parse_request(request_json) }
            end
            
            1000 / result[:duration]
          },
          
          message_validation_throughput: -> {
            message = build_message
            
            result = measure_time do
              1000.times { expect(message).to be_valid_a2a_message }
            end
            
            1000 / result[:duration]
          }
        }
        
        throughput_tests.each do |test_name, test_proc|
          # Run multiple times for stability
          throughputs = []
          5.times do
            throughputs << test_proc.call
          end
          
          baselines[test_name] = {
            avg_throughput: throughputs.sum / throughputs.length,
            min_throughput: throughputs.min,
            max_throughput: throughputs.max
          }
        end
        
        # Memory usage baselines
        if defined?(GetProcessMem)
          memory_tests = {
            json_rpc_memory: -> {
              initial = GetProcessMem.new.mb
              
              1000.times do |i|
                request = build_json_rpc_request("memory_#{i}", { index: i })
                A2A::Protocol::JsonRpc.parse_request(request.to_json)
              end
              
              GC.start
              final = GetProcessMem.new.mb
              final - initial
            },
            
            message_memory: -> {
              initial = GetProcessMem.new.mb
              
              1000.times do |i|
                message = build_message(text: "Memory test #{i}")
                expect(message).to be_valid_a2a_message
              end
              
              GC.start
              final = GetProcessMem.new.mb
              final - initial
            }
          }
          
          memory_tests.each do |test_name, test_proc|
            memory_usages = []
            3.times do
              memory_usages << test_proc.call
            end
            
            baselines[test_name] = {
              avg_memory_per_1000_ops: memory_usages.sum / memory_usages.length,
              max_memory_per_1000_ops: memory_usages.max
            }
          end
        end
        
        # GC frequency baselines
        if GC.respond_to?(:stat)
          gc_baseline = -> {
            initial_gc = GC.stat
            
            1000.times do |i|
              request = build_json_rpc_request("gc_#{i}", { index: i })
              A2A::Protocol::JsonRpc.parse_request(request.to_json)
            end
            
            final_gc = GC.stat
            {
              total_gc: final_gc[:count] - initial_gc[:count],
              major_gc: final_gc[:major_gc_count] - initial_gc[:major_gc_count],
              minor_gc: final_gc[:minor_gc_count] - initial_gc[:minor_gc_count]
            }
          }
          
          gc_runs = []
          3.times { gc_runs << gc_baseline.call }
          
          baselines[:gc_frequency] = {
            avg_total_gc_per_1000_ops: gc_runs.map { |r| r[:total_gc] }.sum / gc_runs.length,
            avg_major_gc_per_1000_ops: gc_runs.map { |r| r[:major_gc] }.sum / gc_runs.length,
            avg_minor_gc_per_1000_ops: gc_runs.map { |r| r[:minor_gc] }.sum / gc_runs.length
          }
        end
        
        # Save comprehensive baseline
        baseline_data = {
          created_at: Time.current.iso8601,
          ruby_version: RUBY_VERSION,
          ruby_platform: RUBY_PLATFORM,
          gem_version: "1.0.0", # Would be actual gem version
          git_commit: ENV['GIT_COMMIT'] || 'unknown',
          baselines: baselines
        }
        
        save_fixture("performance_regression_baseline.json", baseline_data)
        
        puts "\nPerformance Baselines Created:"
        baselines.each do |category, metrics|
          puts "  #{category}:"
          metrics.each do |metric, value|
            formatted_value = case metric.to_s
                             when /time/
                               "#{(value * 1000).round(3)}ms"
                             when /throughput/
                               "#{value.round(0)} ops/sec"
                             when /memory/
                               "#{value.round(3)}MB"
                             when /gc/
                               "#{value.round(1)} GCs"
                             else
                               value.to_s
                             end
            puts "    #{metric}: #{formatted_value}"
          end
        end
        
        expect(baselines).not_to be_empty
      end
    end

    context "baseline loading and validation" do
      it "loads and validates existing baselines" do
        # Create a sample baseline for testing
        sample_baseline = {
          created_at: (Time.current - 1.day).iso8601,
          ruby_version: RUBY_VERSION,
          baselines: {
            json_rpc_parse: {
              avg_response_time: 0.0005,
              p95_response_time: 0.0008
            },
            json_rpc_throughput: {
              avg_throughput: 2000
            }
          }
        }
        
        save_fixture("test_baseline.json", sample_baseline)
        
        # Load and validate
        loaded_baseline = load_fixture("test_baseline.json")
        
        expect(loaded_baseline).to have_key("created_at")
        expect(loaded_baseline).to have_key("ruby_version")
        expect(loaded_baseline).to have_key("baselines")
        expect(loaded_baseline["baselines"]).to have_key("json_rpc_parse")
        
        # Validate baseline structure
        baseline_age = Time.current - Time.parse(loaded_baseline["created_at"])
        expect(baseline_age).to be > 0
        
        puts "Loaded baseline from #{loaded_baseline['created_at']}"
        puts "Baseline age: #{(baseline_age / 3600).round(1)} hours"
        puts "Ruby version: #{loaded_baseline['ruby_version']}"
      end
    end
  end

  describe "Regression Detection" do
    context "response time regression" do
      it "detects response time regressions" do
        # Create baseline
        baseline_response_times = {
          json_rpc_parse: 0.0005,    # 0.5ms baseline
          message_validation: 0.002,  # 2ms baseline
          task_validation: 0.003     # 3ms baseline
        }
        
        # Measure current performance
        current_performance = {}
        
        # JSON-RPC parsing
        request = build_json_rpc_request("regression_test", { test: true })
        request_json = request.to_json
        
        times = []
        100.times do
          result = measure_time { A2A::Protocol::JsonRpc.parse_request(request_json) }
          times << result[:duration]
        end
        current_performance[:json_rpc_parse] = times.sum / times.length
        
        # Message validation
        message = build_message
        times = []
        100.times do
          result = measure_time { expect(message).to be_valid_a2a_message }
          times << result[:duration]
        end
        current_performance[:message_validation] = times.sum / times.length
        
        # Task validation
        task = build_task
        times = []
        100.times do
          result = measure_time { expect(task).to be_valid_a2a_task }
          times << result[:duration]
        end
        current_performance[:task_validation] = times.sum / times.length
        
        # Detect regressions
        regressions = []
        current_performance.each do |operation, current_time|
          baseline_time = baseline_response_times[operation]
          
          if baseline_time
            regression_ratio = (current_time - baseline_time) / baseline_time
            
            if regression_ratio > REGRESSION_THRESHOLDS[:response_time]
              regressions << {
                operation: operation,
                baseline: baseline_time,
                current: current_time,
                regression_percent: (regression_ratio * 100).round(1),
                threshold_percent: (REGRESSION_THRESHOLDS[:response_time] * 100).round(1)
              }
            end
          end
        end
        
        puts "\nResponse Time Regression Analysis:"
        current_performance.each do |operation, current_time|
          baseline_time = baseline_response_times[operation]
          regression_percent = baseline_time ? ((current_time - baseline_time) / baseline_time * 100).round(1) : 0
          
          status = if regression_percent > (REGRESSION_THRESHOLDS[:response_time] * 100)
                    "REGRESSION"
                  elsif regression_percent > 10
                    "WARNING"
                  else
                    "OK"
                  end
          
          puts "  #{operation}: #{(current_time * 1000).round(3)}ms (baseline: #{(baseline_time * 1000).round(3)}ms) [#{status}]"
          puts "    Change: #{regression_percent > 0 ? '+' : ''}#{regression_percent}%"
        end
        
        if regressions.any?
          puts "\nRegressions Detected:"
          regressions.each do |reg|
            puts "  #{reg[:operation]}: #{reg[:regression_percent]}% slower (threshold: #{reg[:threshold_percent]}%)"
          end
        end
        
        # For this test, we expect no regressions (current performance should be similar to baseline)
        expect(regressions).to be_empty, "Performance regressions detected: #{regressions.map { |r| r[:operation] }.join(', ')}"
      end
    end

    context "throughput regression" do
      it "detects throughput regressions" do
        # Baseline throughput (ops/sec)
        baseline_throughput = {
          json_rpc_parsing: 2000,
          message_validation: 1000,
          batch_processing: 500
        }
        
        # Measure current throughput
        current_throughput = {}
        
        # JSON-RPC parsing throughput
        request = build_json_rpc_request("throughput_test", { test: true })
        request_json = request.to_json
        
        result = measure_time do
          1000.times { A2A::Protocol::JsonRpc.parse_request(request_json) }
        end
        current_throughput[:json_rpc_parsing] = 1000 / result[:duration]
        
        # Message validation throughput
        message = build_message
        result = measure_time do
          1000.times { expect(message).to be_valid_a2a_message }
        end
        current_throughput[:message_validation] = 1000 / result[:duration]
        
        # Batch processing throughput
        batch_requests = (1..100).map { |i| build_json_rpc_request("batch_#{i}", { index: i }) }
        batch_json = batch_requests.to_json
        
        result = measure_time do
          10.times { A2A::Protocol::JsonRpc.parse_request(batch_json) }
        end
        current_throughput[:batch_processing] = 1000 / result[:duration] # 100 requests * 10 iterations
        
        # Detect throughput regressions
        regressions = []
        current_throughput.each do |operation, current_tps|
          baseline_tps = baseline_throughput[operation]
          
          if baseline_tps
            regression_ratio = (baseline_tps - current_tps) / baseline_tps
            
            if regression_ratio > REGRESSION_THRESHOLDS[:throughput]
              regressions << {
                operation: operation,
                baseline: baseline_tps,
                current: current_tps,
                regression_percent: (regression_ratio * 100).round(1),
                threshold_percent: (REGRESSION_THRESHOLDS[:throughput] * 100).round(1)
              }
            end
          end
        end
        
        puts "\nThroughput Regression Analysis:"
        current_throughput.each do |operation, current_tps|
          baseline_tps = baseline_throughput[operation]
          regression_percent = baseline_tps ? ((baseline_tps - current_tps) / baseline_tps * 100).round(1) : 0
          
          status = if regression_percent > (REGRESSION_THRESHOLDS[:throughput] * 100)
                    "REGRESSION"
                  elsif regression_percent > 10
                    "WARNING"
                  else
                    "OK"
                  end
          
          puts "  #{operation}: #{current_tps.round(0)} ops/sec (baseline: #{baseline_tps} ops/sec) [#{status}]"
          puts "    Change: #{regression_percent > 0 ? '-' : '+'}#{regression_percent.abs}%"
        end
        
        if regressions.any?
          puts "\nThroughput Regressions Detected:"
          regressions.each do |reg|
            puts "  #{reg[:operation]}: #{reg[:regression_percent]}% slower (threshold: #{reg[:threshold_percent]}%)"
          end
        end
        
        # For this test, expect no significant throughput regressions
        expect(regressions).to be_empty, "Throughput regressions detected: #{regressions.map { |r| r[:operation] }.join(', ')}"
      end
    end

    context "memory usage regression" do
      it "detects memory usage regressions" do
        skip "GetProcessMem gem not available" unless defined?(GetProcessMem)
        
        # Baseline memory usage (MB per 1000 operations)
        baseline_memory = {
          json_rpc_parsing: 2.0,
          message_processing: 3.0,
          task_processing: 4.0
        }
        
        # Measure current memory usage
        current_memory = {}
        
        # JSON-RPC parsing memory
        initial_memory = GetProcessMem.new.mb
        1000.times do |i|
          request = build_json_rpc_request("memory_regression_#{i}", { index: i })
          A2A::Protocol::JsonRpc.parse_request(request.to_json)
        end
        GC.start
        final_memory = GetProcessMem.new.mb
        current_memory[:json_rpc_parsing] = final_memory - initial_memory
        
        # Message processing memory
        initial_memory = GetProcessMem.new.mb
        1000.times do |i|
          message = build_message(text: "Memory regression test #{i}")
          expect(message).to be_valid_a2a_message
        end
        GC.start
        final_memory = GetProcessMem.new.mb
        current_memory[:message_processing] = final_memory - initial_memory
        
        # Task processing memory
        initial_memory = GetProcessMem.new.mb
        1000.times do |i|
          task = build_task(metadata: { index: i, test: "memory_regression" })
          expect(task).to be_valid_a2a_task
        end
        GC.start
        final_memory = GetProcessMem.new.mb
        current_memory[:task_processing] = final_memory - initial_memory
        
        # Detect memory regressions
        regressions = []
        current_memory.each do |operation, current_mb|
          baseline_mb = baseline_memory[operation]
          
          if baseline_mb
            regression_ratio = (current_mb - baseline_mb) / baseline_mb
            
            if regression_ratio > REGRESSION_THRESHOLDS[:memory_usage]
              regressions << {
                operation: operation,
                baseline: baseline_mb,
                current: current_mb,
                regression_percent: (regression_ratio * 100).round(1),
                threshold_percent: (REGRESSION_THRESHOLDS[:memory_usage] * 100).round(1)
              }
            end
          end
        end
        
        puts "\nMemory Usage Regression Analysis:"
        current_memory.each do |operation, current_mb|
          baseline_mb = baseline_memory[operation]
          regression_percent = baseline_mb ? ((current_mb - baseline_mb) / baseline_mb * 100).round(1) : 0
          
          status = if regression_percent > (REGRESSION_THRESHOLDS[:memory_usage] * 100)
                    "REGRESSION"
                  elsif regression_percent > 15
                    "WARNING"
                  else
                    "OK"
                  end
          
          puts "  #{operation}: #{current_mb.round(3)}MB (baseline: #{baseline_mb}MB) [#{status}]"
          puts "    Change: #{regression_percent > 0 ? '+' : ''}#{regression_percent}%"
        end
        
        if regressions.any?
          puts "\nMemory Regressions Detected:"
          regressions.each do |reg|
            puts "  #{reg[:operation]}: #{reg[:regression_percent]}% more memory (threshold: #{reg[:threshold_percent]}%)"
          end
        end
        
        # Allow some memory variance but not excessive
        expect(regressions).to be_empty, "Memory usage regressions detected: #{regressions.map { |r| r[:operation] }.join(', ')}"
      end
    end

    context "garbage collection regression" do
      it "detects GC frequency regressions" do
        skip "GC.stat not available" unless GC.respond_to?(:stat)
        
        # Baseline GC frequency (GCs per 1000 operations)
        baseline_gc = {
          json_rpc_parsing: 5.0,
          message_processing: 8.0
        }
        
        # Measure current GC frequency
        current_gc = {}
        
        # JSON-RPC parsing GC
        initial_gc = GC.stat
        1000.times do |i|
          request = build_json_rpc_request("gc_regression_#{i}", { index: i })
          A2A::Protocol::JsonRpc.parse_request(request.to_json)
        end
        final_gc = GC.stat
        current_gc[:json_rpc_parsing] = final_gc[:count] - initial_gc[:count]
        
        # Message processing GC
        initial_gc = GC.stat
        1000.times do |i|
          message = build_message(text: "GC regression test #{i}")
          expect(message).to be_valid_a2a_message
        end
        final_gc = GC.stat
        current_gc[:message_processing] = final_gc[:count] - initial_gc[:count]
        
        # Detect GC regressions
        regressions = []
        current_gc.each do |operation, current_gcs|
          baseline_gcs = baseline_gc[operation]
          
          if baseline_gcs
            regression_ratio = (current_gcs - baseline_gcs) / baseline_gcs
            
            if regression_ratio > REGRESSION_THRESHOLDS[:gc_frequency]
              regressions << {
                operation: operation,
                baseline: baseline_gcs,
                current: current_gcs,
                regression_percent: (regression_ratio * 100).round(1),
                threshold_percent: (REGRESSION_THRESHOLDS[:gc_frequency] * 100).round(1)
              }
            end
          end
        end
        
        puts "\nGC Frequency Regression Analysis:"
        current_gc.each do |operation, current_gcs|
          baseline_gcs = baseline_gc[operation]
          regression_percent = baseline_gcs ? ((current_gcs - baseline_gcs) / baseline_gcs * 100).round(1) : 0
          
          status = if regression_percent > (REGRESSION_THRESHOLDS[:gc_frequency] * 100)
                    "REGRESSION"
                  elsif regression_percent > 20
                    "WARNING"
                  else
                    "OK"
                  end
          
          puts "  #{operation}: #{current_gcs} GCs (baseline: #{baseline_gcs} GCs) [#{status}]"
          puts "    Change: #{regression_percent > 0 ? '+' : ''}#{regression_percent}%"
        end
        
        if regressions.any?
          puts "\nGC Frequency Regressions Detected:"
          regressions.each do |reg|
            puts "  #{reg[:operation]}: #{reg[:regression_percent]}% more GCs (threshold: #{reg[:threshold_percent]}%)"
          end
        end
        
        # GC frequency can vary, but shouldn't increase dramatically
        expect(regressions).to be_empty, "GC frequency regressions detected: #{regressions.map { |r| r[:operation] }.join(', ')}"
      end
    end
  end

  describe "Regression Reporting" do
    context "comprehensive regression reports" do
      it "generates detailed regression analysis report" do
        # Simulate a comprehensive regression analysis
        report = {
          analysis_timestamp: Time.current.iso8601,
          ruby_version: RUBY_VERSION,
          platform: RUBY_PLATFORM,
          baseline_date: (Time.current - 1.week).iso8601,
          
          performance_metrics: {
            response_times: {
              json_rpc_parse: {
                baseline: 0.0005,
                current: 0.0006,
                change_percent: 20.0,
                status: "WARNING"
              },
              message_validation: {
                baseline: 0.002,
                current: 0.0019,
                change_percent: -5.0,
                status: "IMPROVED"
              }
            },
            
            throughput: {
              json_rpc_parsing: {
                baseline: 2000,
                current: 1950,
                change_percent: -2.5,
                status: "OK"
              }
            },
            
            memory_usage: {
              json_rpc_parsing: {
                baseline: 2.0,
                current: 2.1,
                change_percent: 5.0,
                status: "OK"
              }
            }
          },
          
          regressions_detected: [],
          warnings: [
            {
              metric: "json_rpc_parse_response_time",
              change_percent: 20.0,
              threshold_percent: 25.0,
              recommendation: "Monitor closely, approaching regression threshold"
            }
          ],
          
          improvements: [
            {
              metric: "message_validation_response_time",
              change_percent: -5.0,
              note: "Performance improvement detected"
            }
          ],
          
          summary: {
            total_metrics_analyzed: 4,
            regressions_count: 0,
            warnings_count: 1,
            improvements_count: 1,
            overall_status: "STABLE"
          }
        }
        
        # Save comprehensive report
        save_fixture("regression_analysis_report.json", report)
        
        puts "\nRegression Analysis Report:"
        puts "Analysis Date: #{report[:analysis_timestamp]}"
        puts "Baseline Date: #{report[:baseline_date]}"
        puts "Ruby Version: #{report[:ruby_version]}"
        puts "Platform: #{report[:platform]}"
        puts "\nSummary:"
        puts "  Overall Status: #{report[:summary][:overall_status]}"
        puts "  Metrics Analyzed: #{report[:summary][:total_metrics_analyzed]}"
        puts "  Regressions: #{report[:summary][:regressions_count]}"
        puts "  Warnings: #{report[:summary][:warnings_count]}"
        puts "  Improvements: #{report[:summary][:improvements_count]}"
        
        if report[:warnings].any?
          puts "\nWarnings:"
          report[:warnings].each do |warning|
            puts "  #{warning[:metric]}: #{warning[:change_percent]}% change"
            puts "    #{warning[:recommendation]}"
          end
        end
        
        if report[:improvements].any?
          puts "\nImprovements:"
          report[:improvements].each do |improvement|
            puts "  #{improvement[:metric]}: #{improvement[:change_percent]}% improvement"
          end
        end
        
        expect(report[:summary][:overall_status]).to eq("STABLE")
      end
    end

    context "regression alerts" do
      it "generates alerts for significant regressions" do
        # Simulate regression detection that would trigger alerts
        regressions = [
          {
            metric: "json_rpc_parse_response_time",
            baseline: 0.0005,
            current: 0.0008,
            change_percent: 60.0,
            threshold_percent: 25.0,
            severity: "HIGH",
            impact: "Core JSON-RPC parsing performance degraded significantly"
          },
          {
            metric: "memory_usage_per_1000_ops",
            baseline: 2.0,
            current: 3.0,
            change_percent: 50.0,
            threshold_percent: 30.0,
            severity: "MEDIUM",
            impact: "Memory usage increased beyond acceptable threshold"
          }
        ]
        
        alert_data = {
          alert_timestamp: Time.current.iso8601,
          alert_level: "CRITICAL",
          regressions_count: regressions.length,
          regressions: regressions,
          
          recommended_actions: [
            "Review recent code changes for performance impact",
            "Run detailed profiling to identify bottlenecks",
            "Consider reverting recent changes if regression is severe",
            "Update performance baselines if changes are intentional"
          ],
          
          investigation_steps: [
            "Compare with previous baseline measurements",
            "Profile memory allocation patterns",
            "Analyze GC behavior changes",
            "Review algorithmic complexity of recent changes"
          ]
        }
        
        save_fixture("performance_regression_alert.json", alert_data)
        
        puts "\nPerformance Regression Alert:"
        puts "Alert Level: #{alert_data[:alert_level]}"
        puts "Timestamp: #{alert_data[:alert_timestamp]}"
        puts "Regressions Detected: #{alert_data[:regressions_count]}"
        
        puts "\nRegression Details:"
        regressions.each do |regression|
          puts "  #{regression[:metric]} (#{regression[:severity]} severity):"
          puts "    Baseline: #{regression[:baseline]}"
          puts "    Current: #{regression[:current]}"
          puts "    Change: +#{regression[:change_percent]}% (threshold: #{regression[:threshold_percent]}%)"
          puts "    Impact: #{regression[:impact]}"
        end
        
        puts "\nRecommended Actions:"
        alert_data[:recommended_actions].each_with_index do |action, index|
          puts "  #{index + 1}. #{action}"
        end
        
        # For this test, we're just validating the alert structure
        expect(alert_data[:alert_level]).to eq("CRITICAL")
        expect(alert_data[:regressions]).not_to be_empty
      end
    end
  end

  describe "Continuous Performance Monitoring" do
    context "trend analysis" do
      it "analyzes performance trends over time" do
        # Simulate historical performance data
        historical_data = (1..30).map do |days_ago|
          date = Time.current - days_ago.days
          
          # Simulate gradual performance degradation
          degradation_factor = 1 + (30 - days_ago) * 0.01 # 1% degradation per day
          
          {
            date: date.iso8601,
            metrics: {
              json_rpc_parse_time: 0.0005 * degradation_factor,
              message_validation_time: 0.002 * degradation_factor,
              throughput: 2000 / degradation_factor,
              memory_usage: 2.0 * degradation_factor
            }
          }
        end
        
        # Analyze trends
        metrics_to_analyze = [:json_rpc_parse_time, :message_validation_time, :throughput, :memory_usage]
        trends = {}
        
        metrics_to_analyze.each do |metric|
          values = historical_data.map { |d| d[:metrics][metric] }
          
          # Simple linear trend calculation
          n = values.length
          sum_x = (1..n).sum
          sum_y = values.sum
          sum_xy = (1..n).zip(values).map { |x, y| x * y }.sum
          sum_x2 = (1..n).map { |x| x * x }.sum
          
          slope = (n * sum_xy - sum_x * sum_y) / (n * sum_x2 - sum_x * sum_x)
          
          # Determine trend direction and significance
          trend_direction = if slope > 0.001
                             "INCREASING"
                           elsif slope < -0.001
                             "DECREASING"
                           else
                             "STABLE"
                           end
          
          trends[metric] = {
            slope: slope,
            direction: trend_direction,
            start_value: values.first,
            end_value: values.last,
            total_change_percent: ((values.last - values.first) / values.first * 100).round(2)
          }
        end
        
        puts "\nPerformance Trend Analysis (30 days):"
        trends.each do |metric, trend|
          puts "  #{metric}:"
          puts "    Direction: #{trend[:direction]}"
          puts "    Total Change: #{trend[:total_change_percent] > 0 ? '+' : ''}#{trend[:total_change_percent]}%"
          puts "    Start Value: #{trend[:start_value].round(6)}"
          puts "    End Value: #{trend[:end_value].round(6)}"
        end
        
        # Identify concerning trends
        concerning_trends = trends.select do |metric, trend|
          (metric.to_s.include?('time') || metric.to_s.include?('memory')) && trend[:total_change_percent] > 20 ||
          metric == :throughput && trend[:total_change_percent] < -20
        end
        
        if concerning_trends.any?
          puts "\nConcerning Trends Detected:"
          concerning_trends.each do |metric, trend|
            puts "  #{metric}: #{trend[:direction]} trend with #{trend[:total_change_percent]}% change"
          end
        end
        
        expect(trends).not_to be_empty
      end
    end
  end
end