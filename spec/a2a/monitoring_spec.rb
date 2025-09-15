# frozen_string_literal: true

require 'spec_helper'

RSpec.describe A2A::Monitoring do
  before do
    described_class.initialize!(A2A.config)
  end

  describe '.initialize!' do
    it 'initializes monitoring components' do
      expect(described_class.metrics).to be_a(A2A::Monitoring::MetricsCollector)
      expect(described_class.logger).to be_a(A2A::Monitoring::StructuredLogger)
      expect(described_class.health_checks).to be_a(A2A::Monitoring::HealthChecker)
    end
  end

  describe '.record_metric' do
    it 'records a metric' do
      expect {
        described_class.record_metric('test_metric', 42, label: 'value')
      }.not_to raise_error
    end
  end

  describe '.increment_counter' do
    it 'increments a counter' do
      expect {
        described_class.increment_counter('test_counter', status: 'success')
      }.not_to raise_error
    end
  end

  describe '.time' do
    it 'times a block of code' do
      result = described_class.time('test_operation') do
        sleep(0.01)
        'test_result'
      end
      
      expect(result).to eq('test_result')
    end

    it 'records timing even when block raises error' do
      expect {
        described_class.time('test_operation') do
          raise StandardError, 'test error'
        end
      }.to raise_error(StandardError, 'test error')
    end
  end
end

RSpec.describe A2A::Monitoring::MetricsCollector do
  let(:config) { A2A.config }
  let(:collector) { described_class.new(config) }

  describe '#record' do
    it 'records a metric' do
      collector.record('test_metric', 42, label: 'value')
      
      metrics = collector.current_metrics
      expect(metrics).not_to be_empty
      expect(metrics.last[:name]).to eq('test_metric')
      expect(metrics.last[:value]).to eq(42)
      expect(metrics.last[:labels]).to eq(label: 'value')
    end
  end

  describe '#increment' do
    it 'increments a counter' do
      collector.increment('test_counter', status: 'success')
      
      metrics = collector.current_metrics
      expect(metrics.last[:name]).to eq('test_counter_total')
      expect(metrics.last[:value]).to eq(1)
    end
  end

  describe '#timing' do
    it 'records timing information' do
      collector.timing('test_operation', 0.123, method: 'test')
      
      metrics = collector.current_metrics
      expect(metrics.last[:name]).to eq('test_operation_duration_seconds')
      expect(metrics.last[:value]).to eq(0.123)
    end
  end

  describe '#flush!' do
    it 'clears metrics buffer' do
      collector.record('test_metric', 42)
      expect(collector.current_metrics).not_to be_empty
      
      collector.flush!
      expect(collector.current_metrics).to be_empty
    end
  end
end

RSpec.describe A2A::Monitoring::StructuredLogger do
  let(:config) { A2A.config }
  let(:logger) { described_class.new(config) }

  describe '#log' do
    it 'logs structured data' do
      expect(config.logger).to receive(:info).with(a_string_matching(/correlation_id/))
      
      logger.log(:info, 'test message', key: 'value')
    end
  end

  describe '#set_correlation_id' do
    it 'sets correlation ID for current thread' do
      logger.set_correlation_id('test-id')
      expect(logger.current_correlation_id).to eq('test-id')
    end
  end

  describe '#with_correlation_id' do
    it 'executes block with correlation ID' do
      result = logger.with_correlation_id('test-id') do
        expect(logger.current_correlation_id).to eq('test-id')
        'test_result'
      end
      
      expect(result).to eq('test_result')
    end

    it 'restores previous correlation ID after block' do
      logger.set_correlation_id('original-id')
      
      logger.with_correlation_id('temp-id') do
        expect(logger.current_correlation_id).to eq('temp-id')
      end
      
      expect(logger.current_correlation_id).to eq('original-id')
    end
  end
end

RSpec.describe A2A::Monitoring::HealthChecker do
  let(:config) { A2A.config }
  let(:checker) { described_class.new(config) }

  describe '#register_check' do
    it 'registers a health check' do
      checker.register_check(:test_check) do
        { status: :healthy, message: 'All good' }
      end
      
      result = checker.check_health
      expect(result[:checks][:test_check][:status]).to eq(:healthy)
    end
  end

  describe '#check_health' do
    before do
      checker.register_check(:healthy_check) do
        { status: :healthy, message: 'OK' }
      end
      
      checker.register_check(:unhealthy_check) do
        { status: :unhealthy, message: 'Not OK' }
      end
    end

    it 'returns overall health status' do
      result = checker.check_health
      
      expect(result[:status]).to eq(:unhealthy)
      expect(result[:checks]).to have_key(:healthy_check)
      expect(result[:checks]).to have_key(:unhealthy_check)
    end

    it 'handles check errors' do
      checker.register_check(:error_check) do
        raise StandardError, 'Check failed'
      end
      
      result = checker.check_health
      expect(result[:checks][:error_check][:status]).to eq(:error)
    end
  end

  describe '#healthy?' do
    it 'returns true when all checks pass' do
      checker.register_check(:test_check) do
        { status: :healthy }
      end
      
      expect(checker.healthy?).to be(true)
    end

    it 'returns false when any check fails' do
      checker.register_check(:failing_check) do
        { status: :unhealthy }
      end
      
      expect(checker.healthy?).to be(false)
    end
  end
end

RSpec.describe A2A::Monitoring::Instrumentation do
  describe '.instrument_request' do
    it 'instruments request processing' do
      request = { method: 'test_method', id: 'test-id' }
      
      result = described_class.instrument_request(request) do
        'test_result'
      end
      
      expect(result).to eq('test_result')
    end

    it 'handles request errors' do
      request = { method: 'test_method', id: 'test-id' }
      
      expect {
        described_class.instrument_request(request) do
          raise StandardError, 'Request failed'
        end
      }.to raise_error(StandardError, 'Request failed')
    end
  end

  describe '.instrument_task' do
    it 'instruments task operations' do
      result = described_class.instrument_task('task-123', 'create') do
        'task_result'
      end
      
      expect(result).to eq('task_result')
    end

    it 'handles task operation errors' do
      expect {
        described_class.instrument_task('task-123', 'update') do
          raise StandardError, 'Task operation failed'
        end
      }.to raise_error(StandardError, 'Task operation failed')
    end
  end
end

RSpec.describe A2A::Monitoring::HealthEndpoints do
  let(:health_checker) { A2A::Monitoring::HealthChecker.new(A2A.config) }
  let(:endpoints) { described_class.new(health_checker) }

  describe '#call' do
    it 'handles health check endpoint' do
      env = { 'PATH_INFO' => '/health' }
      status, headers, body = endpoints.call(env)
      
      expect(status).to be_between(200, 503)
      expect(headers['Content-Type']).to eq('application/json')
      expect(body.first).to be_a(String)
    end

    it 'handles readiness check endpoint' do
      env = { 'PATH_INFO' => '/health/ready' }
      status, headers, body = endpoints.call(env)
      
      expect(status).to be_between(200, 503)
      expect(headers['Content-Type']).to eq('application/json')
    end

    it 'handles liveness check endpoint' do
      env = { 'PATH_INFO' => '/health/live' }
      status, headers, body = endpoints.call(env)
      
      expect(status).to eq(200)
      expect(headers['Content-Type']).to eq('application/json')
    end

    it 'handles metrics endpoint' do
      env = { 'PATH_INFO' => '/metrics' }
      status, headers, body = endpoints.call(env)
      
      expect(status).to eq(200)
      expect(body.first).to be_a(String)
    end

    it 'returns 404 for unknown paths' do
      env = { 'PATH_INFO' => '/unknown' }
      status, headers, body = endpoints.call(env)
      
      expect(status).to eq(404)
      expect(headers['Content-Type']).to eq('application/json')
    end
  end
end

RSpec.describe A2A::Monitoring::HealthMiddleware do
  let(:app) { proc { |env| [200, {}, ['OK']] } }
  let(:middleware) { described_class.new(app) }

  it 'passes non-health requests to app' do
    env = { 'PATH_INFO' => '/api/test' }
    status, headers, body = middleware.call(env)
    
    expect(status).to eq(200)
    expect(body).to eq(['OK'])
  end

  it 'handles health requests directly' do
    env = { 'PATH_INFO' => '/health' }
    status, headers, body = middleware.call(env)
    
    expect(status).to be_between(200, 503)
    expect(headers['Content-Type']).to eq('application/json')
  end
end

RSpec.describe A2A do
  after do
    A2A.reset_configuration!
  end

  describe '.initialize_monitoring!' do
    it 'initializes monitoring system' do
      A2A.initialize_monitoring!
      
      expect(A2A::Monitoring.metrics).to be_a(A2A::Monitoring::MetricsCollector)
      expect(A2A::Monitoring.logger).to be_a(A2A::Monitoring::StructuredLogger)
    end
  end

  describe '.record_metric' do
    before { A2A.initialize_monitoring! }

    it 'records a metric' do
      expect {
        A2A.record_metric('test_metric', 42, label: 'value')
      }.not_to raise_error
    end
  end

  describe '.time' do
    before { A2A.initialize_monitoring! }

    it 'times a block of code' do
      result = A2A.time('test_operation') do
        'test_result'
      end
      
      expect(result).to eq('test_result')
    end
  end
end