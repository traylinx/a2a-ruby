# <%= class_name.humanize %> A2A Agent

<%= agent_description %>

## Overview

This agent provides A2A (Agent2Agent) protocol endpoints for <%= class_name.humanize.downcase %> functionality. It was generated using the A2A Ruby SDK Rails generator.

## Endpoints

### Agent Card
- **URL**: `<%= agent_card_path %>`
- **Method**: GET
- **Description**: Returns the agent card with capabilities and interface information

### JSON-RPC Interface
- **URL**: `<%= rpc_path %>`
- **Method**: POST
- **Content-Type**: application/json
- **Description**: Handles A2A JSON-RPC method calls

## Skills and Capabilities

<% if skills.any? %>
This agent provides the following skills:

<% skills.each do |skill| %>
### <%= skill.humanize %>
- **Method**: `<%= skill.underscore %>`
- **Description**: <%= skill.humanize %> functionality
- **Tags**: `<%= skill %>`, `generated`

<% end %>
<% else %>
### Default Processing
- **Method**: `process`
- **Description**: Default <%= class_name.humanize.downcase %> processing functionality
- **Tags**: `<%= class_name.underscore %>`, `default`
<% end %>

### Status
- **Method**: `status`
- **Description**: Get agent status and health information
- **Tags**: `status`, `health`

## Usage Examples

### Get Agent Card
```bash
curl -X GET <%= agent_card_path %>
```

### Call Agent Method
```bash
curl -X POST <%= rpc_path %> \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "status",
    "params": {},
    "id": 1
  }'
```

<% if skills.any? %>
<% skills.first(2).each do |skill| %>
### <%= skill.humanize %> Example
```bash
curl -X POST <%= rpc_path %> \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "<%= skill.underscore %>",
    "params": {
      "action": "<%= skill %>"
    },
    "id": 1
  }'
```
<% end %>
<% end %>

<% if with_authentication? %>
## Authentication

This agent requires authentication for certain methods:

<% authentication_methods.each do |method| %>
- `<%= method %>` - Requires valid authentication
<% end %>

### Authentication Example
```bash
curl -X POST <%= rpc_path %> \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "jsonrpc": "2.0",
    "method": "<%= authentication_methods.first %>",
    "params": {},
    "id": 1
  }'
```
<% end %>

## Development

### Customizing the Agent

1. **Add New Skills**: Define new skills using the `a2a_skill` DSL in the controller
2. **Implement Methods**: Add method implementations using the `a2a_method` DSL
3. **Configure Authentication**: Customize authentication requirements using `a2a_authenticate`

### Example: Adding a New Skill

```ruby
# In <%= controller_file_path %>

a2a_skill "new_feature" do |skill|
  skill.description = "Description of the new feature"
  skill.tags = ["new", "feature"]
  skill.examples = [
    {
      input: { param: "value" },
      output: { result: "success" }
    }
  ]
end

a2a_method "new_feature" do |params|
  # Implement your logic here
  {
    result: "Feature implemented",
    params: params,
    timestamp: Time.current.iso8601
  }
end
```

### Testing

Run the generated tests:

```bash
# RSpec
bundle exec rspec spec/controllers/<%= namespace ? "#{namespace}/" : "" %><%= file_name %>_controller_spec.rb

# Or Rails test
bundle exec rails test test/controllers/<%= namespace ? "#{namespace}/" : "" %><%= file_name %>_controller_test.rb
```

### Debugging

Use the Rails console to test your agent:

```ruby
# Start Rails console
rails console

# Test agent methods directly
controller = <%= controller_class_name %>.new
controller.request = ActionDispatch::Request.new({})

# Generate agent card
card = controller.send(:generate_agent_card)
puts JSON.pretty_generate(card.to_h)

# Test method execution
result = controller.send(:handle_a2a_request, 
  A2A::Protocol::JsonRpc::Request.new(
    jsonrpc: "2.0",
    method: "status",
    params: {},
    id: 1
  )
)
puts JSON.pretty_generate(result)
```

## Configuration

The agent inherits configuration from `config/initializers/a2a.rb`. You can customize:

- Authentication requirements
- Middleware settings
- Storage backends
- Logging levels

## Documentation

- [A2A Protocol Specification](https://a2a-protocol.org/)
- [A2A Ruby SDK Documentation](https://a2a-protocol.org/sdk/ruby/)
- [Rails Integration Guide](https://a2a-protocol.org/sdk/ruby/rails/)

## Support

For issues and questions:
- Check the [A2A Ruby SDK Issues](https://github.com/a2aproject/a2a-ruby/issues)
- Review the [Rails Integration Documentation](https://a2a-protocol.org/sdk/ruby/rails/)
- Join the [A2A Community](https://a2a-protocol.org/community/)