# frozen_string_literal: true

module A2A
  module Protocol
    ##
    # Represents a capability definition for A2A methods
    #
    # Capabilities define the methods that an agent can perform,
    # including input/output schemas, validation rules, and metadata.
    #
    # @example Defining a capability
    #   capability = A2A::Protocol::Capability.new(
    #     name: "analyze_text",
    #     description: "Analyze text content for sentiment and topics",
    #     method: "text/analyze",
    #     input_schema: {
    #       type: "object",
    #       properties: {
    #         text: { type: "string" },
    #         options: { type: "object" }
    #       },
    #       required: ["text"]
    #     },
    #     output_schema: {
    #       type: "object",
    #       properties: {
    #         sentiment: { type: "string" },
    #         topics: { type: "array", items: { type: "string" } }
    #       }
    #     }
    #   )
    #
    class Capability
      attr_reader :name, :description, :method, :input_schema, :output_schema,
                  :examples, :tags, :security_requirements, :metadata,
                  :streaming_supported, :async_supported

      ##
      # Initialize a new capability
      #
      # @param name [String] Capability name (required)
      # @param description [String] Capability description (required)
      # @param method [String] A2A method name (required)
      # @param input_schema [Hash, nil] JSON Schema for input validation
      # @param output_schema [Hash, nil] JSON Schema for output validation
      # @param examples [Array<Hash>, nil] Usage examples
      # @param tags [Array<String>, nil] Capability tags
      # @param security_requirements [Array<String>, nil] Required security schemes
      # @param metadata [Hash, nil] Additional metadata
      # @param streaming_supported [Boolean] Whether streaming is supported
      # @param async_supported [Boolean] Whether async execution is supported
      def initialize(name:, description:, method:, input_schema: nil, output_schema: nil,
                     examples: nil, tags: nil, security_requirements: nil, metadata: nil,
                     streaming_supported: false, async_supported: false)
        @name = name
        @description = description
        @method = method
        @input_schema = input_schema
        @output_schema = output_schema
        @examples = examples
        @tags = tags
        @security_requirements = security_requirements
        @metadata = metadata
        @streaming_supported = streaming_supported
        @async_supported = async_supported

        validate!
      end

      ##
      # Validate input data against the input schema
      #
      # @param input [Hash] The input data to validate
      # @return [Boolean] True if valid
      # @raise [ArgumentError] If validation fails
      def validate_input(input)
        return true if @input_schema.nil?

        validate_against_schema(input, @input_schema, "input")
      end

      ##
      # Validate output data against the output schema
      #
      # @param output [Hash] The output data to validate
      # @return [Boolean] True if valid
      # @raise [ArgumentError] If validation fails
      def validate_output(output)
        return true if @output_schema.nil?

        validate_against_schema(output, @output_schema, "output")
      end

      ##
      # Check if the capability supports streaming
      #
      # @return [Boolean] True if streaming is supported
      def streaming?
        @streaming_supported == true
      end

      ##
      # Check if the capability supports async execution
      #
      # @return [Boolean] True if async is supported
      def async?
        @async_supported == true
      end

      ##
      # Check if the capability has a specific tag
      #
      # @param tag [String] The tag to check
      # @return [Boolean] True if the tag is present
      def has_tag?(tag)
        return false if @tags.nil?

        @tags.include?(tag)
      end

      ##
      # Check if the capability requires a specific security scheme
      #
      # @param scheme [String] The security scheme to check
      # @return [Boolean] True if the scheme is required
      def requires_security?(scheme)
        return false if @security_requirements.nil?

        @security_requirements.include?(scheme)
      end

      ##
      # Convert to hash representation
      #
      # @return [Hash] The capability as a hash
      def to_h
        {
          name: @name,
          description: @description,
          method: @method,
          input_schema: @input_schema,
          output_schema: @output_schema,
          examples: @examples,
          tags: @tags,
          security_requirements: @security_requirements,
          metadata: @metadata,
          streaming_supported: @streaming_supported,
          async_supported: @async_supported
        }.compact
      end

      ##
      # Create from hash representation
      #
      # @param hash [Hash] The hash to create from
      # @return [Capability] The new capability instance
      def self.from_h(hash)
        return nil if hash.nil?

        # Convert string keys to symbols
        normalized_hash = {}
        hash.each do |key, value|
          snake_key = key.to_s.gsub(/([A-Z])/, '_\1').downcase.to_sym
          normalized_hash[snake_key] = value
        end

        new(**normalized_hash)
      end

      private

      def validate!
        if @name.nil? || (respond_to?(:empty?) && empty?) || (is_a?(String) && strip.empty?)
          raise ArgumentError,
                "name is required"
        end
        if @description.nil? || (respond_to?(:empty?) && empty?) || (is_a?(String) && strip.empty?)
          raise ArgumentError,
                "description is required"
        end
        if @method.nil? || (respond_to?(:empty?) && empty?) || (is_a?(String) && strip.empty?)
          raise ArgumentError,
                "method is required"
        end

        raise ArgumentError, "name must be a String" unless @name.is_a?(String)
        raise ArgumentError, "description must be a String" unless @description.is_a?(String)
        raise ArgumentError, "method must be a String" unless @method.is_a?(String)

        validate_schema(@input_schema, "input_schema") if @input_schema
        validate_schema(@output_schema, "output_schema") if @output_schema
        validate_examples if @examples
        validate_array_of_strings(@tags, "tags") if @tags
        validate_array_of_strings(@security_requirements, "security_requirements") if @security_requirements
        validate_hash(@metadata, "metadata") if @metadata
        validate_boolean(@streaming_supported, "streaming_supported")
        validate_boolean(@async_supported, "async_supported")
      end

      ##
      # Validate that a value is a boolean
      def validate_boolean(value, field_name)
        return if value.is_a?(TrueClass) || value.is_a?(FalseClass)

        raise ArgumentError, "#{field_name} must be a Boolean"
      end

      ##
      # Validate that a value is a hash
      def validate_hash(value, field_name)
        return if value.is_a?(Hash)

        raise ArgumentError, "#{field_name} must be a Hash"
      end

      ##
      # Validate that a value is an array of strings
      def validate_array_of_strings(value, field_name)
        raise ArgumentError, "#{field_name} must be an Array" unless value.is_a?(Array)

        value.each_with_index do |item, index|
          raise ArgumentError, "#{field_name}[#{index}] must be a String" unless item.is_a?(String)
        end
      end

      ##
      # Validate that a schema is a valid JSON Schema
      def validate_schema(schema, field_name)
        raise ArgumentError, "#{field_name} must be a Hash" unless schema.is_a?(Hash)

        # Basic JSON Schema validation - check for type field
        return if schema.key?(:type) || schema.key?("type")

        raise ArgumentError, "#{field_name} must have a 'type' field"
      end

      ##
      # Validate examples structure
      def validate_examples
        raise ArgumentError, "examples must be an Array" unless @examples.is_a?(Array)

        @examples.each_with_index do |example, index|
          raise ArgumentError, "examples[#{index}] must be a Hash" unless example.is_a?(Hash)

          # Examples should have at least input or description
          unless example.key?(:input) || example.key?("input") ||
                 example.key?(:description) || example.key?("description")
            raise ArgumentError, "examples[#{index}] must have 'input' or 'description'"
          end
        end
      end

      ##
      # Validate data against a JSON Schema (basic implementation)
      #
      # @param data [Object] The data to validate
      # @param schema [Hash] The JSON Schema
      # @param context [String] Context for error messages
      def validate_against_schema(data, schema, context)
        type = schema[:type] || schema["type"]

        case type
        when "object"
          validate_object(data, schema, context)
        when "array"
          validate_array(data, schema, context)
        when "string"
          validate_string(data, context)
        when "number", "integer"
          validate_number(data, context)
        when "boolean"
          validate_boolean_value(data, context)
        else
          # Allow unknown types for extensibility
          true
        end
      end

      ##
      # Validate object type
      def validate_object(data, schema, context)
        raise ArgumentError, "#{context} must be an object" unless data.is_a?(Hash)

        # Check required properties
        required = schema[:required] || schema["required"] || []
        required.each do |prop|
          raise ArgumentError, "#{context} missing required property: #{prop}" unless data.key?(prop) || data.key?(prop.to_sym)
        end

        # Validate properties if schema defines them
        properties = schema[:properties] || schema["properties"]
        properties&.each do |prop_name, prop_schema|
          prop_value = data[prop_name] || data[prop_name.to_sym]
          validate_against_schema(prop_value, prop_schema, "#{context}.#{prop_name}") if prop_value
        end

        true
      end

      ##
      # Validate array type
      def validate_array(data, schema, context)
        raise ArgumentError, "#{context} must be an array" unless data.is_a?(Array)

        # Validate items if schema defines them
        items_schema = schema[:items] || schema["items"]
        if items_schema
          data.each_with_index do |item, index|
            validate_against_schema(item, items_schema, "#{context}[#{index}]")
          end
        end

        true
      end

      ##
      # Validate string type
      def validate_string(data, context)
        raise ArgumentError, "#{context} must be a string" unless data.is_a?(String)

        true
      end

      ##
      # Validate number type
      def validate_number(data, context)
        raise ArgumentError, "#{context} must be a number" unless data.is_a?(Numeric)

        true
      end

      ##
      # Validate boolean type
      def validate_boolean_value(data, context)
        raise ArgumentError, "#{context} must be a boolean" unless data.is_a?(TrueClass) || data.is_a?(FalseClass)

        true
      end
    end

    ##
    # Manages a registry of capabilities
    #
    # The capability registry allows for registration, discovery, and
    # dynamic updates of agent capabilities.
    #
    class CapabilityRegistry
      def initialize
        @capabilities = {}
        @listeners = []
      end

      ##
      # Register a capability
      #
      # @param capability [Capability] The capability to register
      # @return [Capability] The registered capability
      def register(capability)
        raise ArgumentError, "capability must be a Capability instance" unless capability.is_a?(Capability)

        @capabilities[capability.name] = capability
        notify_listeners(:registered, capability)
        capability
      end

      ##
      # Unregister a capability
      #
      # @param name [String] The capability name to unregister
      # @return [Capability, nil] The unregistered capability or nil if not found
      def unregister(name)
        capability = @capabilities.delete(name)
        notify_listeners(:unregistered, capability) if capability
        capability
      end

      ##
      # Get a capability by name
      #
      # @param name [String] The capability name
      # @return [Capability, nil] The capability or nil if not found
      def get(name)
        @capabilities[name]
      end

      ##
      # Get all registered capabilities
      #
      # @return [Array<Capability>] All capabilities
      def all
        @capabilities.values
      end

      ##
      # Find capabilities by tag
      #
      # @param tag [String] The tag to search for
      # @return [Array<Capability>] Capabilities with the tag
      def find_by_tag(tag)
        @capabilities.values.select { |cap| cap.has_tag?(tag) }
      end

      ##
      # Find capabilities by method pattern
      #
      # @param pattern [String, Regexp] The method pattern to match
      # @return [Array<Capability>] Matching capabilities
      def find_by_method(pattern)
        if pattern.is_a?(String)
          @capabilities.values.select { |cap| cap.method == pattern }
        elsif pattern.is_a?(Regexp)
          @capabilities.values.select { |cap| cap.method.match?(pattern) }
        else
          raise ArgumentError, "pattern must be a String or Regexp"
        end
      end

      ##
      # Find capabilities requiring specific security
      #
      # @param scheme [String] The security scheme
      # @return [Array<Capability>] Capabilities requiring the scheme
      def find_by_security(scheme)
        @capabilities.values.select { |cap| cap.requires_security?(scheme) }
      end

      ##
      # Check if a capability is registered
      #
      # @param name [String] The capability name
      # @return [Boolean] True if registered
      def registered?(name)
        @capabilities.key?(name)
      end

      ##
      # Get the number of registered capabilities
      #
      # @return [Integer] The count
      def count
        @capabilities.size
      end

      ##
      # Clear all capabilities
      def clear
        old_capabilities = @capabilities.values
        @capabilities.clear
        old_capabilities.each { |cap| notify_listeners(:unregistered, cap) }
      end

      ##
      # Add a listener for capability changes
      #
      # @param listener [Proc] The listener proc that receives (event, capability)
      def add_listener(&listener)
        @listeners << listener
      end

      ##
      # Remove a listener
      #
      # @param listener [Proc] The listener to remove
      def remove_listener(listener)
        @listeners.delete(listener)
      end

      ##
      # Convert registry to hash representation
      #
      # @return [Hash] The registry as a hash
      def to_h
        {
          capabilities: @capabilities.transform_values(&:to_h),
          count: count
        }
      end

      private

      ##
      # Notify all listeners of a capability event
      #
      # @param event [Symbol] The event type (:registered, :unregistered)
      # @param capability [Capability] The capability involved
      def notify_listeners(event, capability)
        @listeners.each do |listener|
          listener.call(event, capability)
        rescue StandardError => e
          # Log error but don't let listener errors break the registry
          warn "Capability registry listener error: #{e.message}"
        end
      end
    end
  end
end
