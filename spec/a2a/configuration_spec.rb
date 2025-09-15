# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe A2A::Configuration do
  let(:config) { described_class.new }

  describe '#initialize' do
    it 'sets default values' do
      expect(config.default_timeout).to eq(30)
      expect(config.log_level).to eq(:info)
      expect(config.protocol_version).to eq("0.3.0")
      expect(config.default_transport).to eq("JSONRPC")
      expect(config.streaming_enabled).to be(true)
    end

    it 'detects environment' do
      expect(config.environment).to be_a(String)
    end

    it 'applies overrides' do
      config = described_class.new(default_timeout: 60, log_level: :debug)
      expect(config.default_timeout).to eq(60)
      expect(config.log_level).to eq(:debug)
    end
  end

  describe 'environment variable support' do
    around do |example|
      original_env = ENV.to_h
      example.run
      ENV.replace(original_env)
    end

    it 'loads configuration from environment variables' do
      ENV['A2A_DEFAULT_TIMEOUT'] = '60'
      ENV['A2A_LOG_LEVEL'] = 'debug'
      ENV['A2A_STREAMING_ENABLED'] = 'false'
      ENV['A2A_DEFAULT_INPUT_MODES'] = 'text/plain,application/json'

      config = described_class.new
      expect(config.default_timeout).to eq(60)
      expect(config.log_level).to eq(:debug)
      expect(config.streaming_enabled).to be(false)
      expect(config.default_input_modes).to eq(['text/plain', 'application/json'])
    end

    it 'handles boolean environment variables correctly' do
      ENV['A2A_STREAMING_ENABLED'] = 'true'
      config = described_class.new
      expect(config.streaming_enabled).to be(true)

      ENV['A2A_STREAMING_ENABLED'] = 'false'
      config = described_class.new
      expect(config.streaming_enabled).to be(false)

      ENV['A2A_STREAMING_ENABLED'] = '1'
      config = described_class.new
      expect(config.streaming_enabled).to be(true)

      ENV['A2A_STREAMING_ENABLED'] = '0'
      config = described_class.new
      expect(config.streaming_enabled).to be(false)
    end
  end

  describe '#load_from_file' do
    let(:config_content) do
      <<~YAML
        development:
          default_timeout: 45
          log_level: debug
          streaming_enabled: true
          redis_config:
            url: redis://localhost:6379/1

        test:
          default_timeout: 15
          log_level: warn
          streaming_enabled: false

        production:
          default_timeout: 60
          log_level: error
          authentication_required: true
      YAML
    end

    it 'loads configuration from YAML file' do
      Tempfile.create(['a2a_config', '.yml']) do |file|
        file.write(config_content)
        file.rewind

        config.load_from_file(file.path, environment: 'test')
        expect(config.default_timeout).to eq(15)
        expect(config.log_level).to eq(:warn)
        expect(config.streaming_enabled).to be(false)
      end
    end

    it 'supports ERB in YAML files' do
      erb_content = <<~YAML
        development:
          default_timeout: <%= 30 + 15 %>
          protocol_version: "<%= '0.3.0' %>"
      YAML

      Tempfile.create(['a2a_config', '.yml']) do |file|
        file.write(erb_content)
        file.rewind

        config.load_from_file(file.path, environment: 'development')
        expect(config.default_timeout).to eq(45)
        expect(config.protocol_version).to eq("0.3.0")
      end
    end

    it 'raises error for missing file' do
      expect {
        config.load_from_file('/nonexistent/file.yml')
      }.to raise_error(A2A::Errors::ConfigurationError, /Configuration file not found/)
    end
  end

  describe '#child' do
    it 'creates child configuration with inheritance' do
      parent = described_class.new(default_timeout: 60, log_level: :debug)
      child = parent.child(default_timeout: 30)

      expect(child.default_timeout).to eq(30)
      expect(child.log_level).to eq(:debug) # inherited
      expect(child.parent_config).to eq(parent)
    end
  end

  describe '#merge!' do
    it 'merges configuration from another instance' do
      config1 = described_class.new(default_timeout: 30, log_level: :info)
      config2 = described_class.new(default_timeout: 60, streaming_enabled: false)

      config1.merge!(config2)
      expect(config1.default_timeout).to eq(60)
      expect(config1.streaming_enabled).to be(false)
      expect(config1.log_level).to eq(:info) # unchanged
    end
  end

  describe '#to_h' do
    it 'converts configuration to hash' do
      hash = config.to_h
      expect(hash).to be_a(Hash)
      expect(hash[:default_timeout]).to eq(30)
      expect(hash[:log_level]).to eq(:info)
      expect(hash[:environment]).to be_a(String)
    end
  end

  describe '#validate!' do
    it 'validates basic configuration' do
      expect { config.validate! }.not_to raise_error
    end

    it 'raises error for invalid timeout' do
      config.default_timeout = -1
      expect {
        config.validate!
      }.to raise_error(A2A::Errors::ConfigurationError, /default_timeout must be positive/)
    end

    it 'raises error for blank protocol version' do
      config.protocol_version = ""
      expect {
        config.validate!
      }.to raise_error(A2A::Errors::ConfigurationError, /protocol_version cannot be blank/)
    end

    it 'raises error for invalid transport' do
      config.default_transport = "INVALID"
      expect {
        config.validate!
      }.to raise_error(A2A::Errors::ConfigurationError, /default_transport must be one of/)
    end

    it 'raises error for invalid log level' do
      config.log_level = :invalid
      expect {
        config.validate!
      }.to raise_error(A2A::Errors::ConfigurationError, /log_level must be one of/)
    end
  end
end

RSpec.describe A2A do
  describe '.configure' do
    after { A2A.reset_configuration! }

    it 'yields configuration for block configuration' do
      A2A.configure do |config|
        config.default_timeout = 45
        config.log_level = :debug
      end

      expect(A2A.config.default_timeout).to eq(45)
      expect(A2A.config.log_level).to eq(:debug)
    end

    it 'validates configuration after setup' do
      expect {
        A2A.configure do |config|
          config.default_timeout = -1
        end
      }.to raise_error(A2A::Errors::ConfigurationError)
    end
  end

  describe '.configure_from_file' do
    let(:config_content) do
      <<~YAML
        test:
          default_timeout: 25
          log_level: warn
      YAML
    end

    after { A2A.reset_configuration! }

    it 'configures from YAML file' do
      Tempfile.create(['a2a_config', '.yml']) do |file|
        file.write(config_content)
        file.rewind

        A2A.configure_from_file(file.path, environment: 'test')
        expect(A2A.config.default_timeout).to eq(25)
        expect(A2A.config.log_level).to eq(:warn)
      end
    end
  end

  describe '.child_config' do
    after { A2A.reset_configuration! }

    it 'creates child configuration' do
      A2A.configure { |c| c.default_timeout = 60 }
      child = A2A.child_config(log_level: :debug)

      expect(child.default_timeout).to eq(60) # inherited
      expect(child.log_level).to eq(:debug) # overridden
    end
  end
end