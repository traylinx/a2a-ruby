# frozen_string_literal: true

require "yaml"
require "erb"

module A2A
  class Configuration
    # Module for loading configuration from YAML files
    module FileLoader
      # Load configuration from YAML file
      # @param file_path [String] Path to YAML configuration file
      # @param environment [String, nil] Environment section to load
      # @return [self]
      def load_from_file(file_path, environment: nil)
        @config_file = file_path
        environment ||= @environment

        # Validate file exists and is readable
        raise A2A::Errors::ConfigurationError, "Configuration file not found: #{file_path}" unless File.exist?(file_path)

        raise A2A::Errors::ConfigurationError, "Configuration file not readable: #{file_path}" unless File.readable?(file_path)

        begin
          content = File.read(file_path)

          # Process ERB if the file contains ERB syntax
          erb_content = if content.include?("<%") || content.include?("%>")
                          ERB.new(content).result
                        else
                          content
                        end

          # Parse YAML with proper error handling
          config_data = YAML.safe_load(erb_content, aliases: true, symbolize_names: false) || {}

          unless config_data.is_a?(Hash)
            raise A2A::Errors::ConfigurationError,
                  "Configuration file must contain a hash/dictionary at root level"
          end
        rescue Psych::SyntaxError => e
          raise A2A::Errors::ConfigurationError,
                "Invalid YAML syntax in configuration file #{file_path}: #{e.message}"
        rescue StandardError => e
          raise A2A::Errors::ConfigurationError,
                "Failed to load configuration file #{file_path}: #{e.message}"
        end

        # Load environment-specific configuration
        env_config = config_data[environment.to_s] || config_data[environment.to_sym] || {}

        unless env_config.is_a?(Hash)
          raise A2A::Errors::ConfigurationError,
                "Environment configuration for '#{environment}' must be a hash/dictionary"
        end

        # Apply configuration from file with validation
        begin
          apply_hash_config(env_config)
        rescue StandardError => e
          raise A2A::Errors::ConfigurationError,
                "Failed to apply configuration from file #{file_path}: #{e.message}"
        end

        self
      end

      private

      # Apply configuration from hash
      def apply_hash_config(config_hash)
        unknown_keys = []

        config_hash.each do |key, value|
          key_str = key.to_s
          setter = "#{key_str}="

          if respond_to?(setter)
            begin
              # Special handling for log_level to normalize from string to symbol
              if key_str == "log_level" && value.is_a?(String)
                normalized_value = value.downcase
                valid_levels = %w[debug info warn error fatal]
                value = normalized_value.to_sym if valid_levels.include?(normalized_value)
              end
              send(setter, value)
            rescue StandardError => e
              raise A2A::Errors::ConfigurationError,
                    "Failed to set #{key_str}: #{e.message}"
            end
          else
            # Handle nested configurations
            case key_str
            when "redis_config", "redis"
              if value.is_a?(Hash)
                @redis_config = value.transform_keys(&:to_sym)
              elsif value.is_a?(String)
                @redis_config = { url: value }
              else
                raise A2A::Errors::ConfigurationError,
                      "redis_config must be a hash or URL string, got: #{value.class}"
              end
            else
              unknown_keys << key_str
            end
          end
        end

        # Warn about unknown keys but don't fail
        return if unknown_keys.empty?

        logger&.warn("Unknown configuration keys: #{unknown_keys.join(', ')}")
      end
    end
  end
end
