# A2A Ruby SDK

[![Gem Version](https://badge.fury.io/rb/a2a-ruby.svg)](https://badge.fury.io/rb/a2a-ruby)
[![Build Status](https://github.com/a2aproject/a2a-ruby/workflows/CI/badge.svg)](https://github.com/a2aproject/a2a-ruby/actions)
[![Coverage Status](https://coveralls.io/repos/github/a2aproject/a2a-ruby/badge.svg?branch=main)](https://coveralls.io/github/a2aproject/a2a-ruby?branch=main)

The A2A Ruby SDK provides a complete implementation of Google's Agent2Agent (A2A) Protocol for Ruby applications. It enables seamless agent-to-agent communication via JSON-RPC 2.0, gRPC, and HTTP+JSON transports.

## Features

- 🚀 **Complete A2A Protocol Support** - Full implementation of the A2A specification
- 🔄 **Multiple Transports** - JSON-RPC 2.0, gRPC, and HTTP+JSON support
- 📡 **Streaming & Events** - Server-Sent Events for real-time communication
- 🔐 **Security First** - OAuth 2.0, JWT, API Key, and mTLS authentication
- 📋 **Task Management** - Complete task lifecycle with push notifications
- 🎯 **Agent Cards** - Self-describing agent capabilities and discovery
- 🛠 **Rails Integration** - Seamless Rails engine integration
- 📊 **Production Ready** - Comprehensive logging, metrics, and error handling

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'a2a-ruby'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install a2a-ruby

## Quick Start

### Client Usage

```ruby
require 'a2a'

# Create a client
client = A2A::Client::HttpClient.new("https://agent.example.com/a2a")

# Send a message
message = A2A::Types::Message.new(
  message_id: SecureRandom.uuid,
  role: "user",
  parts: [
    A2A::Types::TextPart.new(text: "Hello, agent!")
  ]
)

# Get response (streaming or blocking)
client.send_message(message) do |response|
  case response
  when A2A::Types::Message
    puts "Agent replied: #{response.parts.first.text}"
  when A2A::Types::Task
    puts "Task created: #{response.id}"
  end
end
```

### Server Usage

```ruby
class MyAgentController < ApplicationController
  include A2A::Server::Agent
  
  # Define agent skills
  a2a_skill "greeting" do |skill|
    skill.description = "Greet users in different languages"
    skill.tags = ["greeting", "conversation", "multilingual"]
    skill.examples = ["Hello", "Say hi in Spanish"]
  end
  
  # Define A2A methods
  a2a_method "greet" do |params|
    language = params[:language] || "en"
    name = params[:name] || "there"
    
    greeting = case language
    when "es" then "¡Hola"
    when "fr" then "Bonjour"
    else "Hello"
    end
    
    {
      message: "#{greeting}, #{name}!",
      language: language
    }
  end
  
  # Handle streaming responses
  a2a_method "chat", streaming: true do |params|
    Enumerator.new do |yielder|
      # Yield task status updates
      yielder << A2A::Types::TaskStatusUpdateEvent.new(
        task_id: params[:task_id],
        context_id: params[:context_id],
        status: A2A::Types::TaskStatus.new(state: "working")
      )
      
      # Process and yield response
      response = process_chat(params[:message])
      yielder << A2A::Types::Message.new(
        message_id: SecureRandom.uuid,
        role: "agent",
        parts: [A2A::Types::TextPart.new(text: response)]
      )
    end
  end
end
```

### Rails Integration

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount A2A::Engine => "/a2a"
end

# The engine automatically provides:
# POST /a2a/rpc          - JSON-RPC endpoint
# GET  /a2a/agent-card   - Agent card discovery
# GET  /a2a/capabilities - Capabilities endpoint
```

## Configuration

```ruby
A2A.configure do |config|
  config.protocol_version = "0.3.0"
  config.default_transport = "JSONRPC"
  config.streaming_enabled = true
  config.push_notifications_enabled = true
  config.default_timeout = 30
  config.log_level = :info
end
```

## Documentation

📚 **[Complete Documentation](docs/README.md)** - Comprehensive guides and references

**Quick Links:**
- [Getting Started Guide](docs/getting_started.md) - Installation to first agent
- [Rails Integration](docs/rails.md) - Full Rails integration guide  
- [Sinatra Integration](docs/sinatra.md) - Lightweight web services
- [Plain Ruby Usage](docs/plain_ruby.md) - CLI tools and standalone apps
- [API Reference](docs/api_reference.md) - Complete API documentation
- [Deployment Guide](docs/deployment.md) - Production deployment
- [Troubleshooting](docs/troubleshooting.md) - Common issues and solutions
- [FAQ](docs/faq.md) - Frequently asked questions

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/a2aproject/a2a-ruby. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/a2aproject/a2a-ruby/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the A2A Ruby project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/a2aproject/a2a-ruby/blob/main/CODE_OF_CONDUCT.md).