# Configuration Reference

This document provides comprehensive configuration options for the A2A Ruby SDK.

## Table of Contents

- [Global Configuration](#global-configuration)
- [Client Configuration](#client-configuration)
- [Server Configuration](#server-configuration)
- [Transport Configuration](#transport-configuration)
- [Authentication Configuration](#authentication-configuration)
- [Storage Configuration](#storage-configuration)
- [Logging Configuration](#logging-configuration)
- [Performance Configuration](#performance-configuration)
- [Environment Variables](#environment-variables)

## Global Configuration

Configure the A2A SDK globally using the `A2A.configure` method:

```ruby
# config/initializers/a2a.rb (Rails)
# or at the top of your application

A2A.configure do |config|
  # Protocol settings
  config.protocol_version = "0.3.0"
  config.default_transport = "JSONRPC"
  
  # Feature flags
  config.streaming_enabled = true
  config.push_notifications_enabled = true
  
  # Timeouts
  config.default_timeout = 30
  config.connect_timeout = 10
  
  # Security
  config.force_ssl = true
  config.ssl_verify = true
end
```

### Protocol Settings

#### protocol_version
- **Type:** String
- **Default:** `"0.3.0"`
- **Description:** A2A protocol version to use

```ruby
config.protocol_version = "0.3.0"
```

#### default_transport
- **Type:** String
- **Default:** `"JSONRPC"`
- **Options:** `"JSONRPC"`, `"GRPC"`, `"HTTP+JSON"`
- **Description:** Default transport protocol for clients

```ruby
config.default_transport = "JSONRPC"
```

### Feature Flags

#### streaming_enabled
- **Type:** Boolean
- **Default:** `true`
- **Description:** Enable streaming responses globally

```ruby
config.streaming_enabled = true
```

#### push_notifications_enabled
- **Type:** Boolean
- **Default:** `true`
- **Description:** Enable push notification support

```ruby
config.push_notifications_enabled = true
```

#### rails_integration
- **Type:** Boolean
- **Default:** `true` (when Rails is detected)
- **Description:** Enable Rails-specific features

```ruby
config.rails_integration = true
```

### Timeout Settings

#### default_timeout
- **Type:** Integer
- **Default:** `30`
- **Unit:** Seconds
- **Description:** Default request timeout

```ruby
config.default_timeout = 60  # 1 minute
```

#### connect_timeout
- **Type:** Integer
- **Default:** `10`
- **Unit:** Seconds
- **Description:** Connection establishment timeout

```ruby
config.connect_timeout = 5  # 5 seconds
```

#### read_timeout
- **Type:** Integer
- **Default:** `30`
- **Unit:** Seconds
- **Description:** Response read timeout

```ruby
config.read_timeout = 45  # 45 seconds
```

### Security Settings

#### force_ssl
- **Type:** Boolean
- **Default:** `true` (production), `false` (development)
- **Description:** Require HTTPS for all connections

```ruby
config.force_ssl = Rails.env.production?
```

#### ssl_verify
- **Type:** Boolean
- **Default:** `true`
- **Description:** Verify SSL certificates

```ruby
config.ssl_verify = true
```

#### allowed_hosts
- **Type:** Array<String>
- **Default:** `[]` (no restrictions)
- **Description:** Restrict connections to specific hosts

```ruby
config.allowed_hosts = ["agent1.example.com", "agent2.example.com"]
```

## Client Configuration

Configure individual clients using `A2A::Client::Config`:

```ruby
config = A2A::Client::Config.new

# Streaming settings
config.streaming = true
config.polling = false
config.polling_interval = 5

# Transport settings
config.supported_transports = ['JSONRPC', 'GRPC']
config.use_client_preference = true

# Output settings
config.accepted_output_modes = ['text', 'structured']

# Timeout settings
config.timeout = 60
config.connect_timeout = 10

# Retry settings
config.max_retries = 3
config.retry_delay = 1
config.retry_backoff = 2

client = A2A::Client::HttpClient.new(url, config: config)
```

### Streaming Configuration

#### streaming
- **Type:** Boolean
- **Default:** `true`
- **Description:** Enable streaming responses for this client

#### polling
- **Type:** Boolean
- **Default:** `false`
- **Description:** Enable polling fallback when streaming fails

#### polling_interval
- **Type:** Integer
- **Default:** `5`
- **Unit:** Seconds
- **Description:** Polling interval for task status updates

### Transport Configuration

#### supported_transports
- **Type:** Array<String>
- **Default:** `['JSONRPC']`
- **Options:** `'JSONRPC'`, `'GRPC'`, `'HTTP+JSON'`
- **Description:** Transport protocols supported by client

#### use_client_preference
- **Type:** Boolean
- **Default:** `true`
- **Description:** Use client transport preference in negotiation

### Output Configuration

#### accepted_output_modes
- **Type:** Array<String>
- **Default:** `['text', 'structured']`
- **Options:** `'text'`, `'structured'`, `'binary'`
- **Description:** Output modes accepted by client

### Retry Configuration

#### max_retries
- **Type:** Integer
- **Default:** `3`
- **Description:** Maximum number of retry attempts

#### retry_delay
- **Type:** Integer
- **Default:** `1`
- **Unit:** Seconds
- **Description:** Initial delay between retries

#### retry_backoff
- **Type:** Float
- **Default:** `2.0`
- **Description:** Backoff multiplier for retry delays

## Server Configuration

Configure A2A servers and agents:

```ruby
class MyAgent
  include A2A::Server::Agent
  
  # Agent metadata
  a2a_config(
    name: "My Agent",
    description: "A sample A2A agent",
    version: "1.0.0",
    url: "https://myagent.example.com/a2a",
    provider: {
      name: "My Company",
      url: "https://mycompany.com"
    }
  )
  
  # Global agent settings
  a2a_settings do |settings|
    settings.max_concurrent_tasks = 10
    settings.task_timeout = 300
    settings.enable_task_history = true
    settings.history_length = 100
  end
end
```

### Agent Metadata

#### name
- **Type:** String
- **Required:** Yes
- **Description:** Human-readable agent name

#### description
- **Type:** String
- **Required:** Yes
- **Description:** Agent description

#### version
- **Type:** String
- **Required:** Yes
- **Description:** Agent version (semantic versioning recommended)

#### url
- **Type:** String
- **Required:** No
- **Description:** Agent endpoint URL

#### provider
- **Type:** Hash
- **Required:** No
- **Description:** Provider information
  - `name` (String) - Provider name
  - `url` (String) - Provider URL

### Agent Settings

#### max_concurrent_tasks
- **Type:** Integer
- **Default:** `10`
- **Description:** Maximum concurrent tasks per agent

#### task_timeout
- **Type:** Integer
- **Default:** `300`
- **Unit:** Seconds
- **Description:** Default task timeout

#### enable_task_history
- **Type:** Boolean
- **Default:** `true`
- **Description:** Store task message history

#### history_length
- **Type:** Integer
- **Default:** `100`
- **Description:** Maximum messages in task history

## Transport Configuration

### HTTP Transport

```ruby
A2A.configure do |config|
  config.http_adapter = :net_http_persistent
  config.http_pool_size = 5
  config.http_keep_alive = 30
  config.http_user_agent = "A2A-Ruby/#{A2A::VERSION}"
end
```

#### http_adapter
- **Type:** Symbol
- **Default:** `:net_http`
- **Options:** `:net_http`, `:net_http_persistent`, `:typhoeus`
- **Description:** Faraday adapter for HTTP transport

#### http_pool_size
- **Type:** Integer
- **Default:** `5`
- **Description:** HTTP connection pool size

#### http_keep_alive
- **Type:** Integer
- **Default:** `30`
- **Unit:** Seconds
- **Description:** HTTP keep-alive timeout

### gRPC Transport

```ruby
A2A.configure do |config|
  config.grpc_enabled = true
  config.grpc_pool_size = 5
  config.grpc_keepalive_time = 30
  config.grpc_keepalive_timeout = 5
end
```

#### grpc_enabled
- **Type:** Boolean
- **Default:** `false`
- **Description:** Enable gRPC transport support

#### grpc_pool_size
- **Type:** Integer
- **Default:** `5`
- **Description:** gRPC connection pool size

### Server-Sent Events

```ruby
A2A.configure do |config|
  config.sse_heartbeat_interval = 30
  config.sse_reconnect_delay = 5
  config.sse_max_reconnects = 10
end
```

#### sse_heartbeat_interval
- **Type:** Integer
- **Default:** `30`
- **Unit:** Seconds
- **Description:** SSE heartbeat interval

#### sse_reconnect_delay
- **Type:** Integer
- **Default:** `5`
- **Unit:** Seconds
- **Description:** Delay before SSE reconnection

## Authentication Configuration

### OAuth 2.0

```ruby
auth = A2A::Client::Auth::OAuth2.new(
  client_id: ENV['A2A_CLIENT_ID'],
  client_secret: ENV['A2A_CLIENT_SECRET'],
  token_url: ENV['A2A_TOKEN_URL'],
  scope: "a2a:read a2a:write",
  audience: "https://api.example.com"
)
```

### JWT

```ruby
auth = A2A::Client::Auth::JWT.new(
  token: ENV['A2A_JWT_TOKEN'],
  header: "Authorization",  # or custom header
  prefix: "Bearer"         # token prefix
)
```

### API Key

```ruby
# Header-based
auth = A2A::Client::Auth::ApiKey.new(
  key: ENV['A2A_API_KEY'],
  header: "X-API-Key"
)

# Query parameter
auth = A2A::Client::Auth::ApiKey.new(
  key: ENV['A2A_API_KEY'],
  parameter: "api_key"
)
```

### Server Authentication

```ruby
# config/initializers/a2a.rb
A2A.configure do |config|
  config.server_auth_strategy = :jwt
  config.jwt_secret = ENV['JWT_SECRET']
  config.jwt_algorithm = 'HS256'
  config.jwt_issuer = 'your-app'
  config.jwt_audience = 'a2a-agents'
end
```

## Storage Configuration

### Database Storage

```ruby
A2A.configure do |config|
  config.storage_backend = :database
  config.database_url = ENV['DATABASE_URL']
  config.database_pool_size = 5
  config.database_timeout = 5000
end
```

### Redis Storage

```ruby
A2A.configure do |config|
  config.storage_backend = :redis
  config.redis_url = ENV['REDIS_URL']
  config.redis_pool_size = 5
  config.redis_timeout = 5
  config.redis_namespace = 'a2a'
end
```

### Memory Storage

```ruby
A2A.configure do |config|
  config.storage_backend = :memory
  config.memory_max_tasks = 1000
  config.memory_cleanup_interval = 300
end
```

## Logging Configuration

```ruby
A2A.configure do |config|
  # Log level
  config.log_level = :info  # :debug, :info, :warn, :error
  
  # Request/response logging
  config.log_requests = false
  config.log_responses = false
  config.log_request_bodies = false
  config.log_response_bodies = false
  
  # Custom logger
  config.logger = Rails.logger  # or custom logger
  
  # Log format
  config.log_format = :json  # :text, :json
  
  # Structured logging
  config.structured_logging = true
  config.log_correlation_id = true
end
```

### Log Levels

- `debug` - Detailed debugging information
- `info` - General information messages
- `warn` - Warning messages
- `error` - Error messages only

### Custom Logger

```ruby
require 'logger'

custom_logger = Logger.new(STDOUT)
custom_logger.formatter = proc do |severity, datetime, progname, msg|
  "[#{datetime}] #{severity}: #{msg}\n"
end

A2A.configure do |config|
  config.logger = custom_logger
end
```

## Performance Configuration

### Metrics

```ruby
A2A.configure do |config|
  config.enable_metrics = true
  config.metrics_backend = :prometheus  # :prometheus, :statsd, :custom
  config.metrics_namespace = 'a2a'
  config.metrics_tags = { service: 'my-agent' }
end
```

### Rate Limiting

```ruby
A2A.configure do |config|
  config.rate_limit_enabled = true
  config.rate_limit_requests = 100
  config.rate_limit_window = 60
  config.rate_limit_storage = :redis  # :memory, :redis
end
```

### Caching

```ruby
A2A.configure do |config|
  config.enable_caching = true
  config.cache_backend = :redis  # :memory, :redis, :rails
  config.cache_ttl = 300  # 5 minutes
  config.cache_namespace = 'a2a_cache'
end
```

### Connection Pooling

```ruby
A2A.configure do |config|
  config.connection_pool_size = 10
  config.connection_pool_timeout = 5
  config.connection_keep_alive = 30
end
```

## Environment Variables

The A2A SDK supports configuration via environment variables:

### General Settings

```bash
# Protocol
A2A_PROTOCOL_VERSION=0.3.0
A2A_DEFAULT_TRANSPORT=JSONRPC

# Timeouts
A2A_DEFAULT_TIMEOUT=30
A2A_CONNECT_TIMEOUT=10

# Security
A2A_FORCE_SSL=true
A2A_SSL_VERIFY=true
```

### Authentication

```bash
# OAuth 2.0
A2A_CLIENT_ID=your-client-id
A2A_CLIENT_SECRET=your-client-secret
A2A_TOKEN_URL=https://auth.example.com/token
A2A_SCOPE=a2a:read a2a:write

# JWT
A2A_JWT_TOKEN=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
A2A_JWT_SECRET=your-jwt-secret

# API Key
A2A_API_KEY=your-api-key
```

### Storage

```bash
# Database
A2A_STORAGE_BACKEND=database
DATABASE_URL=postgresql://user:pass@localhost/db

# Redis
A2A_STORAGE_BACKEND=redis
REDIS_URL=redis://localhost:6379/0
```

### Logging

```bash
A2A_LOG_LEVEL=info
A2A_LOG_REQUESTS=false
A2A_LOG_RESPONSES=false
A2A_LOG_FORMAT=json
```

### Performance

```bash
A2A_ENABLE_METRICS=true
A2A_METRICS_BACKEND=prometheus
A2A_RATE_LIMIT_ENABLED=true
A2A_RATE_LIMIT_REQUESTS=100
```

## Configuration Validation

The SDK validates configuration at startup:

```ruby
A2A.configure do |config|
  config.protocol_version = "invalid"  # Will raise error
end

# Raises A2A::Errors::InvalidConfiguration
```

### Validation Rules

- `protocol_version` must be a valid semantic version
- `default_transport` must be a supported transport
- Timeout values must be positive integers
- Storage backend must be available
- Authentication credentials must be valid format

## Configuration Precedence

Configuration is resolved in this order (highest to lowest priority):

1. Explicit configuration in code
2. Environment variables
3. Configuration files
4. Default values

```ruby
# 1. Explicit (highest priority)
A2A.configure { |c| c.timeout = 60 }

# 2. Environment variable
ENV['A2A_DEFAULT_TIMEOUT'] = '45'

# 3. Configuration file
# config/a2a.yml: timeout: 30

# 4. Default value: 30

# Result: timeout = 60 (explicit wins)
```

## Configuration Files

### YAML Configuration

```yaml
# config/a2a.yml
development:
  protocol_version: "0.3.0"
  default_transport: "JSONRPC"
  streaming_enabled: true
  log_level: debug
  storage_backend: memory

production:
  protocol_version: "0.3.0"
  default_transport: "JSONRPC"
  streaming_enabled: true
  log_level: info
  storage_backend: database
  force_ssl: true
```

Load configuration:

```ruby
config_file = Rails.root.join('config', 'a2a.yml')
config_data = YAML.load_file(config_file)[Rails.env]

A2A.configure do |config|
  config_data.each do |key, value|
    config.send("#{key}=", value)
  end
end
```

## Dynamic Configuration

Some settings can be changed at runtime:

```ruby
# Change log level
A2A.configuration.log_level = :debug

# Enable/disable features
A2A.configuration.streaming_enabled = false

# Update timeouts
A2A.configuration.default_timeout = 60
```

Note: Some settings (like storage backend) require restart to take effect.

## Configuration Best Practices

1. **Use environment variables** for sensitive data (API keys, secrets)
2. **Set appropriate timeouts** based on your use case
3. **Enable SSL verification** in production
4. **Use structured logging** for better observability
5. **Configure rate limiting** to protect your services
6. **Enable metrics** for monitoring and debugging
7. **Use connection pooling** for better performance
8. **Validate configuration** in your deployment pipeline

## Troubleshooting Configuration

### Common Issues

**SSL Certificate Errors:**
```ruby
# Temporary fix for development
A2A.configure { |c| c.ssl_verify = false }
```

**Timeout Issues:**
```ruby
# Increase timeouts for slow networks
A2A.configure do |config|
  config.default_timeout = 120
  config.connect_timeout = 30
end
```

**Authentication Failures:**
```ruby
# Enable request logging to debug
A2A.configure do |config|
  config.log_requests = true
  config.log_level = :debug
end
```

For more configuration help, see the [Troubleshooting Guide](troubleshooting.md).