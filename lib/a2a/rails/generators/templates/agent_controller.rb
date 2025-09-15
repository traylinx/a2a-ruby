# frozen_string_literal: true

##
# <%= controller_class_name %>
#
# A2A Agent controller for <%= class_name.humanize.downcase %> functionality.
# This controller provides A2A protocol endpoints for agent-to-agent communication.
#
class <%= controller_class_name %> < <%= controller_parent_class %>
  include A2A::Rails::ControllerHelpers

  # Configure this agent
  a2a_agent name: "<%= class_name.humanize %> Agent",
            description: "<%= agent_description %>",
            version: "1.0.0",
            tags: <%= agent_tags.inspect %>

  <% if with_authentication? %>
  # Configure authentication for specific methods
  <%= authentication_config %>
  <% end %>

  <% if skills.any? %>
  # Define agent skills
  <%= generate_skill_definitions %>
  <% else %>
  # Define agent skills
  a2a_skill "default" do |skill|
    skill.description = "<%= class_name.humanize %> default functionality"
    skill.tags = ["<%= class_name.underscore %>", "default"]
    skill.examples = [
      {
        input: { action: "process" },
        output: { result: "processed" }
      }
    ]
  end
  <% end %>

  # A2A method implementations

  <% if skills.any? %>
  <%= generate_skill_methods %>
  <% else %>
  ##
  # Default processing method
  #
  # @param params [Hash] Request parameters
  # @return [Hash] Processing result
  #
  a2a_method "process" do |params|
    # TODO: Implement your <%= class_name.humanize.downcase %> logic here
    {
      agent: "<%= class_name %>",
      action: "process",
      params: params,
      result: "Processing completed",
      timestamp: Time.now.iso8601
    }
  end
  <% end %>

  ##
  # Get agent status
  #
  # @param params [Hash] Request parameters (unused)
  # @return [Hash] Status information
  #
  a2a_method "status" do |params|
    {
      agent: "<%= class_name %>",
      status: "active",
      version: "1.0.0",
      capabilities: self.class._a2a_capabilities&.map(&:name) || [],
      methods: self.class._a2a_methods&.keys || [],
      timestamp: Time.now.iso8601
    }
  end

  # Standard Rails actions

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

  <% if with_authentication? %>
  private

  # Override authentication methods as needed
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
      # Example: return user roles or permissions
      current_user.roles&.map(&:name) || ["user"]
    else
      ["guest"]
    end
  end
  <% end %>
end