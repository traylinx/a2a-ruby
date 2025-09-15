# A2A Ruby SDK Documentation

Complete documentation for the A2A Ruby SDK - enabling agent-to-agent communication in Ruby applications.

## Quick Start

- **[Getting Started Guide](getting_started.md)** - Installation and first steps
- **[FAQ](faq.md)** - Frequently asked questions
- **[Migration Guide](migration_guide.md)** - Migrating from other A2A SDKs

## Framework Integration

- **[Rails Integration](rails.md)** - Rails engine and generators
- **[Sinatra Integration](sinatra.md)** - Lightweight web services
- **[Plain Ruby Usage](plain_ruby.md)** - CLI tools and standalone apps

## Reference

- **[API Reference](api_reference.md)** - Complete API documentation
- **[Configuration](configuration.md)** - Configuration options
- **[Error Handling](error_handling.md)** - Error management
- **[Deployment](deployment.md)** - Production deployment
- **[Troubleshooting](troubleshooting.md)** - Common issues and solutions

## Key Features

- **Complete A2A Protocol** - Full A2A Protocol v0.3.0 implementation
- **Multiple Transports** - JSON-RPC 2.0, HTTP+JSON, Server-Sent Events, gRPC
- **Authentication** - OAuth 2.0, JWT, API Key, mTLS support
- **Task Management** - Complete lifecycle with push notifications
- **Framework Integration** - Rails engine, Sinatra middleware, plain Ruby
- **Production Ready** - Monitoring, logging, error handling, performance optimization

## Quick Examples

### Client Usage
```ruby
require 'a2a'

client = A2A::Client::HttpClient.new("https://agent.example.com/a2a")
message = A2A::Types::Message.new(
  message_id: SecureRandom.uuid,
  role: "user",
  parts: [A2A::Types::TextPart.new(text: "Hello!")]
)

response = client.send_message(message)
```

### Server Usage
```ruby
class MyAgent
  include A2A::Server::Agent
  
  a2a_method "greet" do |params|
    { message: "Hello, #{params[:name]}!" }
  end
end
```

### Rails Integration
```ruby
# config/routes.rb
mount A2A::Engine => "/a2a"

# app/controllers/agent_controller.rb
class AgentController < ApplicationController
  include A2A::Server::Agent
  
  a2a_method "process" do |params|
    # Your agent logic
  end
end
```

## Support

- **Issues**: [GitHub Issues](https://github.com/a2aproject/a2a-ruby/issues)
- **Contributing**: [Contributing Guide](../CONTRIBUTING.md)
- **License**: [MIT License](../LICENSE.txt)