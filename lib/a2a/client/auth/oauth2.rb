# frozen_string_literal: true

require "faraday"
require "json"
require "base64"

##
# OAuth 2.0 Client Credentials Flow authentication strategy
#
# Implements OAuth 2.0 client credentials flow for machine-to-machine
# authentication with A2A agents.
#
class A2A::Client::Auth::OAuth2
  attr_reader :client_id, :client_secret, :token_url, :scope, :access_token, :expires_at

  ##
  # Initialize OAuth2 authentication
  #
  # @param client_id [String] OAuth2 client ID
  # @param client_secret [String] OAuth2 client secret
  # @param token_url [String] OAuth2 token endpoint URL
  # @param scope [String, nil] Optional scope for the token
  def initialize(client_id:, client_secret:, token_url:, scope: nil)
    @client_id = client_id
    @client_secret = client_secret
    @token_url = token_url
    @scope = scope
    @access_token = nil
    @expires_at = nil
    @token_mutex = Mutex.new
  end

  ##
  # Get a valid access token, refreshing if necessary
  #
  # @return [String] The access token
  def token
    @token_mutex.synchronize do
      refresh_token if token_expired?
      @access_token
    end
  end

  ##
  # Get authorization header value
  #
  # @return [String] The authorization header value
  def authorization_header
    "Bearer #{token}"
  end

  ##
  # Apply authentication to a Faraday request
  #
  # @param request [Faraday::Request] The request to authenticate
  def apply_to_request(request)
    request.headers["Authorization"] = authorization_header
  end

  ##
  # Check if the current token is valid
  #
  # @return [Boolean] True if token is valid and not expired
  def token_valid?
    @access_token && !token_expired?
  end

  ##
  # Force refresh the access token
  #
  # @return [String] The new access token
  def refresh_token!
    @token_mutex.synchronize do
      refresh_token
    end
  end

  ##
  # Clear the current token (force re-authentication)
  def clear_token!
    @token_mutex.synchronize do
      @access_token = nil
      @expires_at = nil
    end
  end

  private

  ##
  # Check if the token is expired
  #
  # @return [Boolean] True if token is expired or will expire soon
  def token_expired?
    return true unless @expires_at

    # Consider token expired if it expires within 30 seconds
    Time.zone.now >= (@expires_at - 30)
  end

  ##
  # Refresh the access token using client credentials flow
  def refresh_token
    connection = Faraday.new do |conn|
      conn.request :url_encoded
      conn.response :json
      conn.adapter Faraday.default_adapter
    end

    # Prepare request parameters
    params = {
      grant_type: "client_credentials",
      client_id: @client_id,
      client_secret: @client_secret
    }
    params[:scope] = @scope if @scope

    # Make token request
    response = connection.post(@token_url, params)

    unless response.success?
      raise A2A::Errors::AuthenticationError, "OAuth2 token request failed: #{response.status} - #{response.body}"
    end

    token_data = response.body

    unless token_data["access_token"]
      raise A2A::Errors::AuthenticationError, "OAuth2 response missing access_token: #{token_data}"
    end

    @access_token = token_data["access_token"]

    # Calculate expiration time
    expires_in = token_data["expires_in"]&.to_i || 3600 # Default to 1 hour
    @expires_at = Time.zone.now + expires_in

    @access_token
  rescue Faraday::Error => e
    raise A2A::Errors::AuthenticationError, "OAuth2 token request failed: #{e.message}"
  end
end
