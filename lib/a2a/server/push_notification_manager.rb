# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'securerandom'

module A2A
  module Server
    ##
    # Manages push notifications for task updates
    #
    # The PushNotificationManager handles webhook delivery, Server-Sent Events,
    # retry logic, and CRUD operations for push notification configurations.
    #
    class PushNotificationManager
      attr_reader :storage, :config

      ##
      # Initialize a new PushNotificationManager
      #
      # @param storage [Object] Storage backend for push notification configs
      # @param config [Hash] Configuration options
      def initialize(storage: nil, config: {})
        @storage = storage || A2A::Server::Storage::Memory.new
        @config = default_config.merge(config)
        @sse_clients = {}
        @retry_queue = []
        @mutex = Mutex.new
      end

      ##
      # Set a push notification config for a task
      #
      # @param task_id [String] The task ID
      # @param config [A2A::Types::PushNotificationConfig, Hash] The notification config
      # @return [A2A::Types::TaskPushNotificationConfig] The created config
      def set_push_notification_config(task_id, config)
        notification_config = config.is_a?(A2A::Types::PushNotificationConfig) ? 
          config : A2A::Types::PushNotificationConfig.from_h(config)
        
        # Generate ID if not provided
        notification_config.instance_variable_set(:@id, SecureRandom.uuid) unless notification_config.id

        task_config = A2A::Types::TaskPushNotificationConfig.new(
          task_id: task_id,
          push_notification_config: notification_config
        )

        @storage.save_push_notification_config(task_config)
        task_config
      end

      ##
      # Get push notification config for a task
      #
      # @param task_id [String] The task ID
      # @param config_id [String, nil] Optional specific config ID
      # @return [A2A::Types::TaskPushNotificationConfig, nil] The config or nil if not found
      def get_push_notification_config(task_id, config_id: nil)
        if config_id
          @storage.get_push_notification_config_by_id(task_id, config_id)
        else
          configs = @storage.list_push_notification_configs(task_id)
          configs.first # Return the first config if no specific ID requested
        end
      end

      ##
      # List all push notification configs for a task
      #
      # @param task_id [String] The task ID
      # @return [Array<A2A::Types::TaskPushNotificationConfig>] List of configs
      def list_push_notification_configs(task_id)
        @storage.list_push_notification_configs(task_id)
      end

      ##
      # Delete a push notification config
      #
      # @param task_id [String] The task ID
      # @param config_id [String] The config ID
      # @return [Boolean] True if deleted, false if not found
      def delete_push_notification_config(task_id, config_id)
        @storage.delete_push_notification_config(task_id, config_id)
      end

      ##
      # Send a task status update notification
      #
      # @param event [A2A::Types::TaskStatusUpdateEvent] The status update event
      # @return [void]
      def notify_task_status_update(event)
        configs = list_push_notification_configs(event.task_id)
        
        configs.each do |config|
          send_webhook_notification(config, 'task_status_update', event)
        end

        # Send to SSE clients
        send_sse_notification(event.task_id, 'task_status_update', event)
      end

      ##
      # Send a task artifact update notification
      #
      # @param event [A2A::Types::TaskArtifactUpdateEvent] The artifact update event
      # @return [void]
      def notify_task_artifact_update(event)
        configs = list_push_notification_configs(event.task_id)
        
        configs.each do |config|
          send_webhook_notification(config, 'task_artifact_update', event)
        end

        # Send to SSE clients
        send_sse_notification(event.task_id, 'task_artifact_update', event)
      end

      ##
      # Register an SSE client for task updates
      #
      # @param task_id [String] The task ID
      # @param client [Object] The SSE client (response object)
      # @return [String] Client ID
      def register_sse_client(task_id, client)
        client_id = SecureRandom.uuid
        
        @mutex.synchronize do
          @sse_clients[task_id] ||= {}
          @sse_clients[task_id][client_id] = client
        end

        client_id
      end

      ##
      # Unregister an SSE client
      #
      # @param task_id [String] The task ID
      # @param client_id [String] The client ID
      # @return [void]
      def unregister_sse_client(task_id, client_id)
        @mutex.synchronize do
          @sse_clients[task_id]&.delete(client_id)
          @sse_clients.delete(task_id) if @sse_clients[task_id]&.empty?
        end
      end

      ##
      # Process retry queue
      #
      # This method should be called periodically to retry failed notifications
      #
      # @return [void]
      def process_retry_queue
        @mutex.synchronize do
          current_time = Time.now
          
          @retry_queue.select! do |retry_item|
            if current_time >= retry_item[:next_retry_at]
              # Attempt retry
              success = send_webhook_notification_internal(
                retry_item[:config],
                retry_item[:event_type],
                retry_item[:event_data],
                retry_item[:attempt]
              )
              
              if success
                false # Remove from queue
              else
                # Schedule next retry if not exceeded max attempts
                if retry_item[:attempt] < @config[:max_retry_attempts]
                  retry_item[:attempt] += 1
                  retry_item[:next_retry_at] = calculate_next_retry_time(retry_item[:attempt])
                  true # Keep in queue
                else
                  false # Remove from queue (max attempts exceeded)
                end
              end
            else
              true # Keep in queue (not time for retry yet)
            end
          end
        end
      end

      private

      ##
      # Send a webhook notification
      #
      # @param config [A2A::Types::TaskPushNotificationConfig] The notification config
      # @param event_type [String] The event type
      # @param event_data [Object] The event data
      # @return [void]
      def send_webhook_notification(config, event_type, event_data)
        success = send_webhook_notification_internal(config, event_type, event_data, 1)
        
        unless success
          # Add to retry queue
          @mutex.synchronize do
            @retry_queue << {
              config: config,
              event_type: event_type,
              event_data: event_data,
              attempt: 1,
              next_retry_at: calculate_next_retry_time(1)
            }
          end
        end
      end

      ##
      # Internal webhook notification sending
      #
      # @param config [A2A::Types::TaskPushNotificationConfig] The notification config
      # @param event_type [String] The event type
      # @param event_data [Object] The event data
      # @param attempt [Integer] The attempt number
      # @return [Boolean] True if successful
      def send_webhook_notification_internal(config, event_type, event_data, attempt)
        uri = URI.parse(config.webhook_url)
        
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.read_timeout = @config[:webhook_timeout]
        http.open_timeout = @config[:webhook_timeout]

        request = Net::HTTP::Post.new(uri.path)
        request['Content-Type'] = 'application/json'
        request['User-Agent'] = "A2A-Ruby/#{A2A::VERSION}"
        
        # Add authentication headers
        config.auth_headers.each { |key, value| request[key] = value }

        # Build payload
        payload = {
          event_type: event_type,
          event_data: event_data.to_h,
          timestamp: Time.now.utc.iso8601,
          attempt: attempt
        }
        
        request.body = JSON.generate(payload)

        response = http.request(request)
        
        # Consider 2xx responses as successful
        response.code.to_i.between?(200, 299)
        
      rescue => e
        warn "Webhook notification failed: #{e.message}" if @config[:log_errors]
        false
      end

      ##
      # Send SSE notification to registered clients
      #
      # @param task_id [String] The task ID
      # @param event_type [String] The event type
      # @param event_data [Object] The event data
      # @return [void]
      def send_sse_notification(task_id, event_type, event_data)
        @mutex.synchronize do
          clients = @sse_clients[task_id]
          return unless clients

          # Build SSE message
          sse_data = {
            event_type: event_type,
            event_data: event_data.to_h,
            timestamp: Time.now.utc.iso8601
          }
          
          sse_message = "event: #{event_type}\n"
          sse_message += "data: #{JSON.generate(sse_data)}\n\n"

          # Send to all clients for this task
          clients.each do |client_id, client|
            begin
              client.write(sse_message)
              client.flush if client.respond_to?(:flush)
            rescue => e
              # Remove disconnected client
              clients.delete(client_id)
              warn "SSE client disconnected: #{e.message}" if @config[:log_errors]
            end
          end

          # Clean up empty task entries
          @sse_clients.delete(task_id) if clients.empty?
        end
      end

      ##
      # Calculate next retry time using exponential backoff
      #
      # @param attempt [Integer] The attempt number
      # @return [Time] The next retry time
      def calculate_next_retry_time(attempt)
        base_delay = @config[:retry_base_delay]
        max_delay = @config[:retry_max_delay]
        
        delay = [base_delay * (2 ** (attempt - 1)), max_delay].min
        
        # Add jitter to prevent thundering herd
        jitter = rand(0.1 * delay)
        
        Time.now + delay + jitter
      end

      ##
      # Default configuration
      #
      # @return [Hash] Default configuration
      def default_config
        {
          webhook_timeout: 30,
          max_retry_attempts: 3,
          retry_base_delay: 1.0, # seconds
          retry_max_delay: 60.0, # seconds
          log_errors: true
        }
      end
    end
  end
end