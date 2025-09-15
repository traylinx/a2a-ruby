# frozen_string_literal: true

require_relative "config"

##
# Abstract base class for A2A clients
#
# Provides the common interface and functionality for all A2A client implementations.
# Concrete clients should inherit from this class and implement the abstract methods.
#
class A2A::Client::Base
  attr_reader :config, :middleware, :consumers

  ##
  # Initialize a new client
  #
  # @param config [Config, nil] Client configuration
  # @param middleware [Array] List of middleware interceptors
  # @param consumers [Array] List of event consumers
  def initialize(config: nil, middleware: [], consumers: [])
    @config = config || Config.new
    @middleware = middleware.dup
    @consumers = consumers.dup
    @task_callbacks = {}
  end

  ##
  # Send a message to the agent
  #
  # @param message [Message, Hash] The message to send
  # @param context [Hash, nil] Optional context information
  # @return [Enumerator, Message] Stream of responses or single response
  # @raise [NotImplementedError] Must be implemented by subclasses
  def send_message(message, context: nil)
    raise NotImplementedError, "#{self.class}#send_message must be implemented"
  end

  ##
  # Get a task by ID
  #
  # @param task_id [String] The task ID
  # @param context [Hash, nil] Optional context information
  # @param history_length [Integer, nil] Maximum number of history messages to include
  # @return [Task] The task
  # @raise [NotImplementedError] Must be implemented by subclasses
  def get_task(task_id, context: nil, history_length: nil)
    raise NotImplementedError, "#{self.class}#get_task must be implemented"
  end

  ##
  # Cancel a task
  #
  # @param task_id [String] The task ID to cancel
  # @param context [Hash, nil] Optional context information
  # @return [Task] The updated task
  # @raise [NotImplementedError] Must be implemented by subclasses
  def cancel_task(task_id, context: nil)
    raise NotImplementedError, "#{self.class}#cancel_task must be implemented"
  end

  ##
  # Get the agent card
  #
  # @param context [Hash, nil] Optional context information
  # @param authenticated [Boolean] Whether to get authenticated extended card
  # @return [AgentCard] The agent card
  # @raise [NotImplementedError] Must be implemented by subclasses
  def get_card(context: nil, authenticated: false)
    raise NotImplementedError, "#{self.class}#get_card must be implemented"
  end

  ##
  # Resubscribe to a task for streaming updates
  #
  # @param task_id [String] The task ID to resubscribe to
  # @param context [Hash, nil] Optional context information
  # @return [Enumerator] Stream of task updates
  # @raise [NotImplementedError] Must be implemented by subclasses
  def resubscribe(task_id, context: nil)
    raise NotImplementedError, "#{self.class}#resubscribe must be implemented"
  end

  ##
  # Set a callback for task updates
  #
  # @param task_id [String] The task ID
  # @param push_notification_config [PushNotificationConfig, Hash] The push notification configuration
  # @param context [Hash, nil] Optional context information
  # @return [void]
  # @raise [NotImplementedError] Must be implemented by subclasses
  def set_task_callback(task_id, push_notification_config, context: nil)
    raise NotImplementedError, "#{self.class}#set_task_callback must be implemented"
  end

  ##
  # Get the callback configuration for a task
  #
  # @param task_id [String] The task ID
  # @param push_notification_config_id [String] The push notification config ID
  # @param context [Hash, nil] Optional context information
  # @return [TaskPushNotificationConfig] The callback configuration
  # @raise [NotImplementedError] Must be implemented by subclasses
  def get_task_callback(task_id, push_notification_config_id, context: nil)
    raise NotImplementedError, "#{self.class}#get_task_callback must be implemented"
  end

  ##
  # List all callback configurations for a task
  #
  # @param task_id [String] The task ID
  # @param context [Hash, nil] Optional context information
  # @return [Array<TaskPushNotificationConfig>] List of callback configurations
  # @raise [NotImplementedError] Must be implemented by subclasses
  def list_task_callbacks(task_id, context: nil)
    raise NotImplementedError, "#{self.class}#list_task_callbacks must be implemented"
  end

  ##
  # Delete a callback configuration for a task
  #
  # @param task_id [String] The task ID
  # @param push_notification_config_id [String] The push notification config ID
  # @param context [Hash, nil] Optional context information
  # @return [void]
  # @raise [NotImplementedError] Must be implemented by subclasses
  def delete_task_callback(task_id, push_notification_config_id, context: nil)
    raise NotImplementedError, "#{self.class}#delete_task_callback must be implemented"
  end

  ##
  # Add middleware to the client
  #
  # @param interceptor [Object] The middleware interceptor
  # @return [void]
  def add_middleware(interceptor)
    @middleware << interceptor
  end

  ##
  # Remove middleware from the client
  #
  # @param interceptor [Object] The middleware interceptor to remove
  # @return [void]
  def remove_middleware(interceptor)
    @middleware.delete(interceptor)
  end

  ##
  # Add an event consumer
  #
  # @param consumer [Object] The event consumer
  # @return [void]
  def add_consumer(consumer)
    @consumers << consumer
  end

  ##
  # Remove an event consumer
  #
  # @param consumer [Object] The event consumer to remove
  # @return [void]
  def remove_consumer(consumer)
    @consumers.delete(consumer)
  end

  ##
  # Check if the client supports streaming
  #
  # @return [Boolean] True if streaming is supported and enabled
  delegate :streaming?, to: :@config

  ##
  # Check if the client supports polling
  #
  # @return [Boolean] True if polling is supported and enabled
  delegate :polling?, to: :@config

  ##
  # Get the supported transports
  #
  # @return [Array<String>] List of supported transport protocols
  delegate :supported_transports, to: :@config

  ##
  # Negotiate transport with agent card
  #
  # @param agent_card [AgentCard] The agent card
  # @return [String] The negotiated transport protocol
  def negotiate_transport(agent_card)
    # Use client preference if enabled
    if @config.use_client_preference?
      preferred = @config.preferred_transport
      return preferred if agent_supports_transport?(agent_card, preferred)
    end

    # Find first mutually supported transport
    @config.supported_transports.each do |transport|
      return transport if agent_supports_transport?(agent_card, transport)
    end

    # Fallback to agent's preferred transport if we support it
    agent_preferred = agent_card.preferred_transport
    return agent_preferred if @config.supports_transport?(agent_preferred)

    # No compatible transport found
    raise A2A::Errors::ClientError, "No compatible transport protocol found"
  end

  ##
  # Get the endpoint URL for a specific transport
  #
  # @param agent_card [AgentCard] The agent card
  # @param transport [String] The transport protocol
  # @return [String] The endpoint URL
  def get_endpoint_url(agent_card, transport)
    # Check if the transport matches the preferred transport
    return agent_card.url if agent_card.preferred_transport == transport

    # Look for the transport in additional interfaces
    interface = agent_card.additional_interfaces&.find { |iface| iface.transport == transport }
    return interface.url if interface

    # Fallback to main URL if no specific interface found
    agent_card.url
  end

  protected

  ##
  # Execute middleware chain for a request
  #
  # @param request [Object] The request object
  # @param context [Hash] The request context
  # @yield [request, context] The block to execute after middleware
  # @return [Object] The result of the block execution
  def execute_with_middleware(request, context = {}, &block)
    # Create a chain of middleware calls
    chain = @middleware.reverse.reduce(proc(&block)) do |next_call, middleware|
      proc { |req, ctx| middleware.call(req, ctx, next_call) }
    end

    # Execute the chain
    chain.call(request, context)
  end

  ##
  # Process events with registered consumers
  #
  # @param event [Object] The event to process
  # @return [void]
  def process_event(event)
    @consumers.each do |consumer|
      consumer.call(event)
    rescue StandardError => e
      # Log error but don't fail the entire processing
      warn "Error in event consumer: #{e.message}"
    end
  end

  ##
  # Convert a message hash or object to a Message instance
  #
  # @param message [Message, Hash] The message to convert
  # @return [Message] The message instance
  def ensure_message(message)
    return message if message.is_a?(A2A::Types::Message)

    A2A::Types::Message.from_h(message)
  end

  ##
  # Convert a task hash or object to a Task instance
  #
  # @param task [Task, Hash] The task to convert
  # @return [Task] The task instance
  def ensure_task(task)
    return task if task.is_a?(A2A::Types::Task)

    A2A::Types::Task.from_h(task)
  end

  ##
  # Convert an agent card hash or object to an AgentCard instance
  #
  # @param agent_card [AgentCard, Hash] The agent card to convert
  # @return [AgentCard] The agent card instance
  def ensure_agent_card(agent_card)
    return agent_card if agent_card.is_a?(A2A::Types::AgentCard)

    A2A::Types::AgentCard.from_h(agent_card)
  end

  private

  ##
  # Check if an agent supports a specific transport
  #
  # @param agent_card [AgentCard] The agent card
  # @param transport [String] The transport to check
  # @return [Boolean] True if the agent supports the transport
  def agent_supports_transport?(agent_card, transport)
    return true if agent_card.preferred_transport == transport

    agent_card.additional_interfaces&.any? { |iface| iface.transport == transport }
  end
end
