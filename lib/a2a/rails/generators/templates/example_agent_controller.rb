# frozen_string_literal: true

##
# Example A2A Agent Controller
#
# This controller demonstrates how to create an A2A agent using the Rails integration.
# It includes examples of skills, capabilities, and method definitions.
#
# To test this agent:
# 1. Start your Rails server
# 2. Visit <%= mount_path %>/agent-card to see the agent card
# 3. Send JSON-RPC requests to <%= mount_path %>/rpc
#
class ExampleAgentController < ApplicationController
  include A2A::Rails::ControllerHelpers

  # Configure this agent
  a2a_agent name: "Example Agent",
            description: "A demonstration A2A agent for Rails integration",
            version: "1.0.0",
            tags: ["example", "demo", "rails"]

  <% if with_authentication? %>
  # Configure authentication (uncomment and customize as needed)
  # a2a_authenticate :<%= authentication_strategy %>, methods: ["secure_greeting"]
  <% end %>

  # Define agent skills
  a2a_skill "greeting" do |skill|
    skill.description = "Greet users with personalized messages"
    skill.tags = ["greeting", "conversation", "social"]
    skill.examples = [
      {
        input: { name: "Alice" },
        output: { message: "Hello, Alice! Welcome to our A2A agent." }
      }
    ]
  end

  a2a_skill "echo" do |skill|
    skill.description = "Echo back any message sent to the agent"
    skill.tags = ["utility", "testing", "echo"]
    skill.examples = [
      {
        input: { message: "Hello, world!" },
        output: { echo: "Hello, world!" }
      }
    ]
  end

  a2a_skill "time" do |skill|
    skill.description = "Get current server time in various formats"
    skill.tags = ["utility", "time", "datetime"]
    skill.examples = [
      {
        input: { format: "iso8601" },
        output: { time: "2024-01-01T12:00:00Z", format: "iso8601" }
      }
    ]
  end

  # A2A method implementations

  ##
  # Greet a user with a personalized message
  #
  # @param params [Hash] Request parameters
  # @option params [String] :name The name to greet
  # @option params [String] :style Greeting style (formal, casual, friendly)
  # @return [Hash] Greeting response
  #
  a2a_method "greeting" do |params|
    name = params[:name] || "there"
    style = params[:style] || "friendly"
    
    message = case style
              when "formal"
                "Good day, #{name}. It is a pleasure to make your acquaintance."
              when "casual"
                "Hey #{name}! What's up?"
              else
                "Hello, #{name}! Welcome to our A2A agent."
              end
    
    {
      message: message,
      name: name,
      style: style,
      timestamp: Time.now.iso8601
    }
  end

  ##
  # Echo back the provided message
  #
  # @param params [Hash] Request parameters
  # @option params [String] :message The message to echo
  # @return [Hash] Echo response
  #
  a2a_method "echo" do |params|
    message = params[:message] || ""
    
    {
      echo: message,
      length: message.length,
      timestamp: Time.now.iso8601,
      agent: "ExampleAgent"
    }
  end

  ##
  # Get current server time
  #
  # @param params [Hash] Request parameters
  # @option params [String] :format Time format (iso8601, unix, human)
  # @option params [String] :timezone Timezone (default: UTC)
  # @return [Hash] Time response
  #
  a2a_method "get_time" do |params|
    format = params[:format] || "iso8601"
    timezone = params[:timezone] || "UTC"
    
    begin
      time = Time.now.in_time_zone(timezone)
      
      formatted_time = case format
                      when "unix"
                        time.to_i
                      when "human"
                        time.strftime("%B %d, %Y at %I:%M %p %Z")
                      else
                        time.iso8601
                      end
      
      {
        time: formatted_time,
        format: format,
        timezone: timezone,
        server_timezone: Time.zone.name
      }
    rescue ArgumentError => e
      raise A2A::Errors::InvalidParams, "Invalid timezone: #{timezone}"
    end
  end

  <% if with_authentication? %>
  ##
  # Secure greeting method (requires authentication)
  #
  # @param params [Hash] Request parameters
  # @option params [String] :message Personal message
  # @return [Hash] Authenticated greeting response
  #
  a2a_method "secure_greeting" do |params|
    message = params[:message] || "Hello from the secure zone!"
    
    {
      message: message,
      user: current_user_info,
      permissions: current_user_permissions,
      authenticated_at: Time.now.iso8601,
      security_level: "authenticated"
    }
  end
  <% end %>

  ##
  # Get agent status and health information
  #
  # @param params [Hash] Request parameters (unused)
  # @return [Hash] Status response
  #
  a2a_method "status" do |params|
    {
      status: "healthy",
      version: "1.0.0",
      uptime: Time.now - Rails.application.config.booted_at,
      rails_version: Rails.version,
      a2a_version: A2A::VERSION,
      capabilities: self.class._a2a_capabilities&.map(&:name) || [],
      methods: self.class._a2a_methods&.keys || [],
      timestamp: Time.now.iso8601
    }
  end

  # Standard Rails actions for agent card and RPC handling

  ##
  # Serve the agent card
  #
  def agent_card
    render_agent_card
  end

  ##
  # Handle JSON-RPC requests
  #
  def rpc
    handle_a2a_rpc
  end

  private

  # Override authentication methods if needed
  <% if with_authentication? %>
  
  def current_user_info
    if respond_to?(:current_user) && current_user.present?
      {
        id: current_user.id,
        email: current_user.email,
        name: current_user.name || current_user.email
      }
    else
      { id: "anonymous", name: "Anonymous User" }
    end
  end

  def current_user_permissions
    # Customize based on your authorization system
    if respond_to?(:current_user) && current_user.present?
      ["read", "write"] # Example permissions
    else
      ["read"] # Anonymous permissions
    end
  end
  <% end %>
end