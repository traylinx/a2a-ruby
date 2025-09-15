# frozen_string_literal: true

module A2A::Types
  ##
  # Represents a push notification configuration
  #
  # Push notification configs define how and where to send notifications
  # about task updates and other events.
  #
  class PushNotificationConfig < BaseModel
    attr_reader :id, :url, :token, :authentication

    ##
    # Initialize a new push notification config
    #
    # @param url [String] The webhook URL
    # @param id [String, nil] Optional config identifier
    # @param token [String, nil] Optional authentication token
    # @param authentication [Hash, nil] Authentication configuration
    def initialize(url:, id: nil, token: nil, authentication: nil)
      @url = url
      @id = id
      @token = token
      @authentication = authentication

      validate!
    end

    ##
    # Check if authentication is configured
    #
    # @return [Boolean] True if authentication is present
    def authenticated?
      !@token.nil? || !@authentication.nil?
    end

    ##
    # Get authentication headers for webhook requests
    #
    # @return [Hash] Headers to include in webhook requests
    def auth_headers
      headers = {}

      headers["Authorization"] = "Bearer #{@token}" if @token

      if @authentication.is_a?(Hash)
        case @authentication["type"]
        when "bearer"
          headers["Authorization"] = "Bearer #{@authentication["token"]}"
        when "basic"
          require "base64"
          credentials = Base64.strict_encode64("#{@authentication["username"]}:#{@authentication["password"]}")
          headers["Authorization"] = "Basic #{credentials}"
        when "api_key"
          key_name = @authentication["key_name"] || "X-API-Key"
          headers[key_name] = @authentication["api_key"]
        end
      end

      headers
    end

    private

    def validate!
      validate_required(:url)
      validate_type(:url, String)

      # Basic URL validation
      begin
        require "uri"
        uri = URI.parse(@url)
        raise ArgumentError, "URL must be HTTP or HTTPS" unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      rescue URI::InvalidURIError
        raise ArgumentError, "Invalid URL: #{@url}"
      end
    end
  end

  ##
  # Represents a task-specific push notification configuration
  #
  # Links a task to a push notification configuration for receiving
  # updates about that specific task.
  #
  class TaskPushNotificationConfig < BaseModel
    attr_reader :task_id, :push_notification_config

    ##
    # Initialize a new task push notification config
    #
    # @param task_id [String] The task identifier
    # @param push_notification_config [PushNotificationConfig, Hash] The notification config
    def initialize(task_id:, push_notification_config:)
      @task_id = task_id
      @push_notification_config = if push_notification_config.is_a?(PushNotificationConfig)
                                    push_notification_config
                                  else
                                    PushNotificationConfig.from_h(push_notification_config)
                                  end

      validate!
    end

    ##
    # Get the webhook URL
    #
    # @return [String] The webhook URL
    def webhook_url
      @push_notification_config.url
    end

    ##
    # Get authentication headers
    #
    # @return [Hash] Authentication headers
    delegate :auth_headers, to: :@push_notification_config

    ##
    # Check if authentication is configured
    #
    # @return [Boolean] True if authentication is present
    delegate :authenticated?, to: :@push_notification_config

    private

    def validate!
      validate_required(:task_id, :push_notification_config)
      validate_type(:task_id, String)
      validate_type(:push_notification_config, PushNotificationConfig)
    end
  end
end
