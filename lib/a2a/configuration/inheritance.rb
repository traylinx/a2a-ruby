# frozen_string_literal: true

module A2A
  class Configuration
    # Module for configuration inheritance support
    module Inheritance
      # Create a child configuration with inheritance
      # @param **overrides [Hash] Configuration overrides
      # @return [Configuration] New configuration instance
      def child(**overrides)
        # Create new instance without loading defaults to avoid overwriting parent values
        child_config = self.class.allocate
        child_config.instance_variable_set(:@environment, @environment)
        child_config.instance_variable_set(:@parent_config, self)
        child_config.instance_variable_set(:@overrides, overrides)
        child_config.instance_variable_set(:@config_file, nil)

        # Copy all instance variables from parent to child (deep copy for complex objects)
        instance_variables.each do |var|
          next if %i[@parent_config @overrides @config_file].include?(var)

          value = instance_variable_get(var)
          # Deep copy arrays and hashes to prevent shared references
          copied_value = case value
                         when Array
                           value.dup
                         when Hash
                           value.dup
                         else
                           value
                         end
          child_config.instance_variable_set(var, copied_value)
        end

        # Apply overrides after copying parent values
        child_config.send(:apply_overrides, overrides)

        child_config
      end

      # Get configuration value with inheritance support
      # @param key [Symbol, String] Configuration key
      # @return [Object] Configuration value
      def get(key)
        # Convert key to instance variable name
        ivar_name = "@#{key}"

        # Check if we have the instance variable set
        if instance_variable_defined?(ivar_name)
          value = instance_variable_get(ivar_name)
          # Return value if it's not nil, or if we don't have a parent
          return value unless value.nil? && @parent_config
        end

        # Fall back to parent configuration if value is nil and parent exists
        @parent_config&.get(key)
      end

      # Validate that child configuration properly inherits from parent
      # @return [Boolean] true if inheritance is working correctly
      def validate_inheritance!
        return true unless @parent_config

        # Check that we can access parent values when child values are nil
        parent_attrs = @parent_config.to_h
        parent_attrs.each do |key, parent_value|
          next if parent_value.nil?

          # Get child value directly (not through inheritance)
          child_ivar = "@#{key}"
          child_value = instance_variable_defined?(child_ivar) ? instance_variable_get(child_ivar) : nil

          # If child value is nil, get should return parent value
          next unless child_value.nil?

          inherited_value = get(key)
          unless inherited_value == parent_value
            raise A2A::Errors::ConfigurationError,
                  "Inheritance failed for #{key}: expected #{parent_value.inspect}, got #{inherited_value.inspect}"
          end
        end

        true
      end

      # Merge configuration from another configuration object
      # @param other [Configuration] Configuration to merge from
      # @return [self]
      def merge!(other)
        return self unless other.is_a?(A2A::Configuration)

        other.to_h.each do |key, value|
          setter = "#{key}="
          send(setter, value) if respond_to?(setter)
        end

        self
      end
    end
  end
end
