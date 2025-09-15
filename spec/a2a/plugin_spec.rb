# frozen_string_literal: true

require 'spec_helper'

# Test plugin classes
class TestTransportPlugin < A2A::Plugin::TransportPlugin
  def transport_name
    'TEST'
  end

  def send_request(request, **options)
    { result: 'test_response', id: request[:id] }
  end

  def supports_streaming?
    true
  end
end

class TestAuthPlugin < A2A::Plugin::AuthPlugin
  def strategy_name
    'test'
  end

  def authenticate_request(request, **options)
    request[:headers] ||= {}
    request[:headers]['Authorization'] = 'Bearer test_token'
    request
  end
end

class TestMiddlewarePlugin < A2A::Plugin::MiddlewarePlugin
  def call(request, next_middleware)
    request[:middleware_processed] = true
    response = next_middleware.call(request)
    response[:middleware_response] = true if response.is_a?(Hash)
    response
  end
end

RSpec.describe A2A::Plugin do
  before do
    described_class.clear!
  end

  after do
    described_class.clear!
  end

  describe '.register' do
    it 'registers a plugin' do
      described_class.register(:test_transport, TestTransportPlugin)
      
      expect(described_class.registry[:test_transport]).to include(
        class: TestTransportPlugin,
        type: :transport,
        loaded: false
      )
    end

    it 'raises error for invalid plugin class' do
      expect {
        described_class.register(:invalid, String)
      }.to raise_error(A2A::Errors::PluginError, /must include A2A::Plugin::Base/)
    end
  end

  describe '.load' do
    before do
      described_class.register(:test_transport, TestTransportPlugin)
    end

    it 'loads a registered plugin' do
      plugin = described_class.load(:test_transport)
      
      expect(plugin).to be_a(TestTransportPlugin)
      expect(described_class.loaded?(:test_transport)).to be(true)
    end

    it 'returns existing instance if already loaded' do
      plugin1 = described_class.load(:test_transport)
      plugin2 = described_class.load(:test_transport)
      
      expect(plugin1).to be(plugin2)
    end

    it 'raises error for unregistered plugin' do
      expect {
        described_class.load(:nonexistent)
      }.to raise_error(A2A::Errors::PluginError, /Plugin not found/)
    end
  end

  describe '.unload' do
    before do
      described_class.register(:test_transport, TestTransportPlugin)
      described_class.load(:test_transport)
    end

    it 'unloads a loaded plugin' do
      described_class.unload(:test_transport)
      
      expect(described_class.loaded?(:test_transport)).to be(false)
    end
  end

  describe '.loaded_plugins' do
    before do
      described_class.register(:test_transport, TestTransportPlugin)
      described_class.register(:test_auth, TestAuthPlugin)
      described_class.load(:test_transport)
      described_class.load(:test_auth)
    end

    it 'returns all loaded plugins' do
      plugins = described_class.loaded_plugins
      expect(plugins.size).to eq(2)
    end

    it 'filters plugins by type' do
      transport_plugins = described_class.loaded_plugins(type: :transport)
      auth_plugins = described_class.loaded_plugins(type: :auth)
      
      expect(transport_plugins.size).to eq(1)
      expect(auth_plugins.size).to eq(1)
      expect(transport_plugins.first).to be_a(TestTransportPlugin)
      expect(auth_plugins.first).to be_a(TestAuthPlugin)
    end
  end

  describe 'hooks' do
    it 'adds and executes hooks' do
      results = []
      
      described_class.add_hook(:test_event) do |data|
        results << "hook1: #{data}"
      end
      
      described_class.add_hook(:test_event) do |data|
        results << "hook2: #{data}"
      end
      
      described_class.execute_hooks(:test_event, 'test_data')
      
      expect(results).to eq(['hook1: test_data', 'hook2: test_data'])
    end

    it 'respects hook priority' do
      results = []
      
      described_class.add_hook(:test_event, priority: 100) do |data|
        results << 'low_priority'
      end
      
      described_class.add_hook(:test_event, priority: 10) do |data|
        results << 'high_priority'
      end
      
      described_class.execute_hooks(:test_event, 'data')
      
      expect(results).to eq(['high_priority', 'low_priority'])
    end
  end
end

RSpec.describe A2A::Plugin::Base do
  let(:plugin_class) do
    Class.new(described_class) do
      plugin_type :test
      depends_on :dependency1, :dependency2
    end
  end

  it 'defines plugin type' do
    expect(plugin_class.plugin_type).to eq(:test)
  end

  it 'defines dependencies' do
    expect(plugin_class.dependencies).to eq([:dependency1, :dependency2])
  end

  it 'initializes with configuration' do
    plugin = plugin_class.new(key: 'value')
    expect(plugin.config).to eq(key: 'value')
  end
end

RSpec.describe A2A::Plugin::TransportPlugin do
  let(:plugin) { TestTransportPlugin.new }

  it 'has transport plugin type' do
    expect(TestTransportPlugin.plugin_type).to eq(:transport)
  end

  it 'implements transport interface' do
    expect(plugin.transport_name).to eq('TEST')
    expect(plugin.supports_streaming?).to be(true)
    
    response = plugin.send_request({ id: 1, method: 'test' })
    expect(response[:result]).to eq('test_response')
  end
end

RSpec.describe A2A::Plugin::AuthPlugin do
  let(:plugin) { TestAuthPlugin.new }

  it 'has auth plugin type' do
    expect(TestAuthPlugin.plugin_type).to eq(:auth)
  end

  it 'implements auth interface' do
    expect(plugin.strategy_name).to eq('test')
    
    request = { id: 1 }
    authenticated = plugin.authenticate_request(request)
    
    expect(authenticated[:headers]['Authorization']).to eq('Bearer test_token')
  end
end

RSpec.describe A2A::Plugin::MiddlewarePlugin do
  let(:plugin) { TestMiddlewarePlugin.new }

  it 'has middleware plugin type' do
    expect(TestMiddlewarePlugin.plugin_type).to eq(:middleware)
  end

  it 'implements middleware interface' do
    request = { id: 1 }
    next_middleware = proc { |req| { response: 'test', id: req[:id] } }
    
    response = plugin.call(request, next_middleware)
    
    expect(request[:middleware_processed]).to be(true)
    expect(response[:middleware_response]).to be(true)
  end
end

RSpec.describe A2A::PluginManager do
  let(:manager) { described_class.new }

  before do
    A2A::Plugin.clear!
    A2A::Plugin.register(:test_transport, TestTransportPlugin)
    A2A::Plugin.register(:test_auth, TestAuthPlugin)
    A2A::Plugin.register(:test_middleware, TestMiddlewarePlugin)
  end

  after do
    A2A::Plugin.clear!
  end

  describe '#configure_plugins' do
    it 'configures auto-loading plugins' do
      manager.configure_plugins({
        test_transport: { auto_load: true },
        test_auth: { auto_load: false }
      })
      
      manager.load_all_plugins
      
      expect(A2A::Plugin.loaded?(:test_transport)).to be(true)
      expect(A2A::Plugin.loaded?(:test_auth)).to be(false)
    end
  end

  describe '#load_plugin' do
    it 'loads a plugin with configuration' do
      plugin = manager.load_plugin(:test_transport, custom_config: 'value')
      
      expect(plugin).to be_a(TestTransportPlugin)
      expect(plugin.config[:custom_config]).to eq('value')
    end
  end

  describe 'plugin type methods' do
    before do
      manager.load_plugin(:test_transport)
      manager.load_plugin(:test_auth)
      manager.load_plugin(:test_middleware)
    end

    it 'returns transport plugins' do
      plugins = manager.transport_plugins
      expect(plugins.size).to eq(1)
      expect(plugins.first).to be_a(TestTransportPlugin)
    end

    it 'returns auth plugins' do
      plugins = manager.auth_plugins
      expect(plugins.size).to eq(1)
      expect(plugins.first).to be_a(TestAuthPlugin)
    end

    it 'returns middleware plugins' do
      plugins = manager.middleware_plugins
      expect(plugins.size).to eq(1)
      expect(plugins.first).to be_a(TestMiddlewarePlugin)
    end
  end

  describe '#status' do
    before do
      manager.load_plugin(:test_transport)
    end

    it 'returns plugin status information' do
      status = manager.status
      
      expect(status[:loaded_plugins]).to eq(1)
      expect(status[:registered_plugins]).to eq(3)
      expect(status[:plugins_by_type][:transport]).to eq(1)
    end
  end
end

RSpec.describe A2A do
  after do
    A2A::Plugin.clear!
    A2A.reset_configuration!
  end

  describe '.register_plugin' do
    it 'registers a plugin' do
      A2A.register_plugin(:test_transport, TestTransportPlugin)
      
      expect(A2A::Plugin.registry[:test_transport]).to be_present
    end
  end

  describe '.load_plugin' do
    before do
      A2A.register_plugin(:test_transport, TestTransportPlugin)
    end

    it 'loads a plugin' do
      plugin = A2A.load_plugin(:test_transport)
      expect(plugin).to be_a(TestTransportPlugin)
    end
  end

  describe '.configure_plugins' do
    before do
      A2A.register_plugin(:test_transport, TestTransportPlugin)
    end

    it 'configures plugins' do
      A2A.configure_plugins({
        test_transport: { auto_load: true }
      })
      
      expect(A2A.plugins.status[:auto_load_plugins]).to include(:test_transport)
    end
  end
end