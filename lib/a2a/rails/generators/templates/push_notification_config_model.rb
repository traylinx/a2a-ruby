# frozen_string_literal: true

##
# <%= model_class_name("push_notification_config") %>
#
# ActiveRecord model for A2A push notification configurations.
# This model stores webhook URLs and authentication details for task notifications.
#
class <%= model_class_name("push_notification_config") %> < ApplicationRecord
  self.table_name = "<%= push_notification_configs_table_name %>"
  self.primary_key = "id"

  # Associations
  belongs_to :<%= model_file_name("task") %>, 
             foreign_key: :task_id, 
             class_name: "<%= model_class_name("task") %>"

  # Validations
  validates :id, presence: true, uniqueness: true
  validates :task_id, presence: true
  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
  validates :retry_count, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # Scopes
  scope :active, -> { where(active: true, deleted_at: nil) }
  scope :inactive, -> { where(active: false) }
  scope :by_task, ->(task_id) { where(task_id: task_id) }
  scope :failed_recently, -> { where("last_failure_at > ?", 1.hour.ago) }
  scope :needs_retry, -> { where("retry_count < ? AND (last_failure_at IS NULL OR last_failure_at < ?)", max_retries, retry_delay.ago) }

  # Callbacks
  before_create :ensure_id
  after_create :log_creation
  after_update :log_status_change, if: :saved_change_to_active?

  # Configuration
  MAX_RETRIES = 5
  RETRY_DELAY = 5.minutes

  def self.max_retries
    MAX_RETRIES
  end

  def self.retry_delay
    RETRY_DELAY
  end

  # Soft delete
  def soft_delete!
    update!(deleted_at: Time.current, active: false)
  end

  def deleted?
    deleted_at.present?
  end

  # Status management
  def mark_success!
    update!(
      last_success_at: Time.current,
      last_failure_at: nil,
      last_error: nil,
      retry_count: 0
    )
  end

  def mark_failure!(error_message)
    update!(
      last_failure_at: Time.current,
      last_error: error_message,
      retry_count: retry_count + 1,
      active: retry_count < self.class.max_retries
    )
  end

  def can_retry?
    active && retry_count < self.class.max_retries && 
    (last_failure_at.nil? || last_failure_at < self.class.retry_delay.ago)
  end

  def should_disable?
    retry_count >= self.class.max_retries
  end

  # Convert to A2A types
  def to_a2a_push_notification_config
    A2A::Types::PushNotificationConfig.new(
      id: id,
      url: url,
      token: token,
      authentication: authentication || {}
    )
  end

  def to_a2a_task_push_notification_config
    A2A::Types::TaskPushNotificationConfig.new(
      task_id: task_id,
      push_notification_config: to_a2a_push_notification_config
    )
  end

  # Create from A2A types
  def self.from_a2a_config(task_id, config)
    if config.is_a?(A2A::Types::TaskPushNotificationConfig)
      pn_config = config.push_notification_config
      task_id = config.task_id
    elsif config.is_a?(A2A::Types::PushNotificationConfig)
      pn_config = config
    else
      raise ArgumentError, "Invalid config type"
    end

    new(
      id: pn_config.id || SecureRandom.uuid,
      task_id: task_id,
      url: pn_config.url,
      token: pn_config.token,
      authentication: pn_config.authentication || {}
    )
  end

  # Webhook delivery
  def deliver_notification(event_data)
    return false unless active? && !deleted?

    begin
      response = send_webhook_request(event_data)
      
      if response.success?
        mark_success!
        true
      else
        mark_failure!("HTTP #{response.code}: #{response.body}")
        false
      end
    rescue => e
      mark_failure!(e.message)
      false
    end
  end

  # Authentication helpers
  def has_authentication?
    authentication.present? && authentication.any?
  end

  def authentication_type
    return nil unless has_authentication?
    
    if authentication["type"].present?
      authentication["type"]
    elsif token.present?
      "bearer"
    else
      "custom"
    end
  end

  # Statistics
  def success_rate
    total_attempts = retry_count + (last_success_at.present? ? 1 : 0)
    return 0.0 if total_attempts == 0
    
    successful_attempts = last_success_at.present? ? 1 : 0
    (successful_attempts.to_f / total_attempts * 100).round(2)
  end

  def last_activity
    [last_success_at, last_failure_at].compact.max
  end

  private

  def ensure_id
    self.id ||= SecureRandom.uuid
  end

  def log_creation
    Rails.logger.info "Created push notification config #{id} for task #{task_id}"
  end

  def log_status_change
    status = active? ? "activated" : "deactivated"
    Rails.logger.info "Push notification config #{id} #{status}"
  end

  def send_webhook_request(event_data)
    require 'faraday'
    
    conn = Faraday.new do |f|
      f.request :json
      f.response :json
      f.adapter Faraday.default_adapter
    end

    headers = build_request_headers
    
    conn.post(url) do |req|
      req.headers.merge!(headers)
      req.body = event_data
    end
  end

  def build_request_headers
    headers = {
      'Content-Type' => 'application/json',
      'User-Agent' => "A2A-Ruby/#{A2A::VERSION}",
      'X-A2A-Task-ID' => task_id,
      'X-A2A-Config-ID' => id
    }

    # Add authentication headers
    case authentication_type
    when "bearer"
      headers['Authorization'] = "Bearer #{token}"
    when "api_key"
      headers['X-API-Key'] = token
    when "custom"
      # Add custom authentication headers from authentication hash
      authentication.each do |key, value|
        next if %w[type].include?(key)
        headers[key] = value
      end
    end

    headers
  end
end