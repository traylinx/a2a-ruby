# frozen_string_literal: true

##
# API Key authentication strategy
#
# Supports API key authentication via headers, query parameters,
# or custom locations as specified by the agent's security scheme.
#
class A2A::Client::Auth::ApiKey
  attr_reader :key, :value, :location, :name

  # Valid locations for API key
  VALID_LOCATIONS = %w[header query cookie].freeze

  ##
  # Initialize API key authentication
  #
  # @param key [String] The API key value
  # @param name [String] The parameter/header name for the API key (default: 'X-API-Key')
  # @param location [String] Where to place the API key: 'header', 'query', or 'cookie' (default: 'header')
  def initialize(key:, name: "X-API-Key", location: "header")
    @key = key
    @name = name
    @location = location.downcase
    @value = key # Alias for consistency

    validate_configuration!
  end

  ##
  # Apply authentication to a Faraday request
  #
  # @param request [Faraday::Request] The request to authenticate
  def apply_to_request(request)
    case @location
    when "header"
      request.headers[@name] = @key
    when "query"
      # Add to query parameters
      request.params[@name] = @key
    when "cookie"
      # Add to cookie header
      existing_cookies = request.headers["Cookie"]
      cookie_value = "#{@name}=#{@key}"

      request.headers["Cookie"] = if existing_cookies
                                    "#{existing_cookies}; #{cookie_value}"
                                  else
                                    cookie_value
                                  end
    end
  end

  ##
  # Get the authentication header (for header-based API keys)
  #
  # @return [Hash] Header name and value
  def authentication_header
    return {} unless @location == "header"

    { @name => @key }
  end

  ##
  # Get the authentication query parameter (for query-based API keys)
  #
  # @return [Hash] Parameter name and value
  def authentication_params
    return {} unless @location == "query"

    { @name => @key }
  end

  ##
  # Check if the API key is valid (basic validation)
  #
  # @return [Boolean] True if key appears valid
  def valid?
    @key.present? && @key.is_a?(String)
  end

  ##
  # Mask the API key for logging (shows only first and last 4 characters)
  #
  # @return [String] Masked API key
  def masked_key
    return "[empty]" if @key.nil? || (respond_to?(:empty?) && empty?) || (is_a?(String) && strip.empty?)
    return @key if @key.length <= 8

    "#{@key[0..3]}#{"*" * (@key.length - 8)}#{@key[-4..]}"
  end

  ##
  # Create API key authentication from security scheme
  #
  # @param scheme [Hash] Security scheme definition
  # @param key_value [String] The API key value
  # @return [ApiKey] Configured API key authentication
  def self.from_security_scheme(scheme, key_value)
    location = scheme["in"] || "header"
    name = scheme["name"] || "X-API-Key"

    new(key: key_value, name: name, location: location)
  end

  ##
  # Convert to hash representation
  #
  # @return [Hash] Configuration as hash
  def to_h
    {
      type: "api_key",
      key: masked_key,
      name: @name,
      location: @location
    }
  end

  ##
  # String representation (with masked key)
  #
  # @return [String] String representation
  def to_s
    "ApiKey(name=#{@name}, location=#{@location}, key=#{masked_key})"
  end

  ##
  # Inspect representation (with masked key)
  #
  # @return [String] Inspect representation
  def inspect
    "#<A2A::Client::Auth::ApiKey:0x#{object_id.to_s(16)} #{self}>"
  end

  private

  ##
  # Validate the authentication configuration
  def validate_configuration!
    raise ArgumentError, "API key cannot be nil or empty" if @key.nil? || (respond_to?(:empty?) && empty?) || (is_a?(String) && strip.empty?)
    raise ArgumentError, "API key must be a string" unless @key.is_a?(String)
    raise ArgumentError, "Name cannot be nil or empty" if @name.nil? || (respond_to?(:empty?) && empty?) || (is_a?(String) && strip.empty?)

    return if VALID_LOCATIONS.include?(@location)

    raise ArgumentError, "Invalid location '#{@location}'. Must be one of: #{VALID_LOCATIONS.join(", ")}"
  end
end
