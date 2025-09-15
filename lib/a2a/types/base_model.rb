# frozen_string_literal: true

require "time"

module A2A
  module Types
  end
end

##
# Base class for all A2A protocol types
#
# Provides common functionality for validation, serialization, and
# camelCase/snake_case conversion for A2A protocol compatibility.
#
class A2A::Types::BaseModel
  ##
  # Initialize a new model instance
  #
  # @param attributes [Hash] The attributes to set
  def initialize(**attributes)
    # Set instance variables for all provided attributes
    attributes.each do |key, value|
      instance_variable_set("@#{key}", value)
    end

    # Validate the instance after initialization
    validate! if respond_to?(:validate!, true)
  end

  ##
  # Convert the model to a hash representation
  #
  # @param camel_case [Boolean] Whether to convert keys to camelCase
  # @return [Hash] The model as a hash
  def to_h(camel_case: true)
    hash = {}

    instance_variables.each do |var|
      key = var.to_s.delete("@")
      value = instance_variable_get(var)

      # Convert nested models
      case value
      when BaseModel
        value = value.to_h(camel_case: camel_case)
      when Array
        value = value.map do |item|
          item.is_a?(BaseModel) ? item.to_h(camel_case: camel_case) : item
        end
      when Hash
        value = value.transform_values do |v|
          v.is_a?(BaseModel) ? v.to_h(camel_case: camel_case) : v
        end
      end

      # Convert key to camelCase if requested
      key = camelize(key) if camel_case
      hash[key] = value unless value.nil?
    end

    hash
  end

  ##
  # Create an instance from a hash
  #
  # @param hash [Hash] The hash to create from
  # @return [BaseModel] The new instance
  def self.from_h(hash)
    return hash if hash.is_a?(self) # Already an instance of this class
    return nil if hash.nil?

    # Convert string keys to symbols and snake_case camelCase keys
    normalized_hash = {}
    hash.each do |key, value|
      snake_key = underscore(key.to_s).to_sym
      normalized_hash[snake_key] = value
    end

    new(**normalized_hash)
  end

  ##
  # Convert to JSON string
  #
  # @param options [Hash] JSON generation options
  # @return [String] The JSON representation
  def to_json(**options)
    require "json"
    to_h.to_json(**options)
  end

  ##
  # Create an instance from JSON string
  #
  # @param json_string [String] The JSON string
  # @return [BaseModel] The new instance
  def self.from_json(json_string)
    require "json"
    hash = JSON.parse(json_string)
    from_h(hash)
  end

  ##
  # Check equality with another model
  #
  # @param other [Object] The other object to compare
  # @return [Boolean] True if equal
  def ==(other)
    return false unless other.is_a?(self.class)

    to_h == other.to_h
  end

  ##
  # Generate hash code for the model
  #
  # @return [Integer] The hash code
  def hash
    to_h.hash
  end

  ##
  # Check if the model is valid
  #
  # @return [Boolean] True if valid
  def valid?
    validate!
    true
  rescue StandardError
    false
  end

  private

  ##
  # Convert snake_case to camelCase
  #
  # @param string [String] The string to convert
  # @return [String] The camelCase string
  def camelize(string)
    string.to_s.gsub(/_([a-z])/) { ::Regexp.last_match(1).upcase }
  end

  ##
  # Convert camelCase to snake_case
  #
  # @param string [String] The string to convert
  # @return [String] The snake_case string
  def self.underscore(string)
    string.to_s
      .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
      .gsub(/([a-z\d])([A-Z])/, '\1_\2')
      .downcase
  end

  ##
  # Validate required fields
  #
  # @param fields [Array<Symbol>] The required field names
  # @raise [ArgumentError] If any required field is missing
  def validate_required(*fields)
    fields.each do |field|
      value = instance_variable_get("@#{field}")
      raise ArgumentError, "#{field} is required" if value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end
  end

  ##
  # Validate that a field is one of the allowed values
  #
  # @param field [Symbol] The field name
  # @param allowed_values [Array] The allowed values
  # @raise [ArgumentError] If the field value is not allowed
  def validate_inclusion(field, allowed_values)
    value = instance_variable_get("@#{field}")
    return if value.nil?

    return if allowed_values.include?(value)

    raise ArgumentError, "#{field} must be one of: #{allowed_values.join(", ")}"
  end

  ##
  # Validate that a field is of the expected type
  #
  # @param field [Symbol] The field name
  # @param expected_type [Class, Array<Class>] The expected type(s)
  # @raise [ArgumentError] If the field is not of the expected type
  def validate_type(field, expected_type)
    value = instance_variable_get("@#{field}")
    return if value.nil?

    types = expected_type.is_a?(Array) ? expected_type : [expected_type]

    return if types.any? { |type| value.is_a?(type) }

    type_names = types.map(&:to_s).join(" or ")
    raise ArgumentError, "#{field} must be a #{type_names}"
  end

  ##
  # Validate that an array field contains only items of the expected type
  #
  # @param field [Symbol] The field name
  # @param expected_type [Class] The expected item type
  # @raise [ArgumentError] If any item is not of the expected type
  def validate_array_type(field, expected_type)
    value = instance_variable_get("@#{field}")
    return if value.nil?

    validate_type(field, Array)

    value.each_with_index do |item, index|
      raise ArgumentError, "#{field}[#{index}] must be a #{expected_type}" unless item.is_a?(expected_type)
    end
  end
end
