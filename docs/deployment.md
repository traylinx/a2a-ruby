# Deployment Guide

This guide covers deploying A2A Ruby SDK applications to various platforms and environments.

## Table of Contents

- [Production Preparation](#production-preparation)
- [Docker Deployment](#docker-deployment)
- [Kubernetes Deployment](#kubernetes-deployment)
- [Heroku Deployment](#heroku-deployment)
- [AWS Deployment](#aws-deployment)
- [Monitoring and Logging](#monitoring-and-logging)
- [Security Considerations](#security-considerations)
- [Performance Optimization](#performance-optimization)
- [Troubleshooting](#troubleshooting)

## Production Preparation

### Environment Configuration

```ruby
# config/environments/production.rb (Rails)
# or config/production.rb (Sinatra/Plain Ruby)

A2A.configure do |config|
  # Protocol settings
  config.protocol_version = "0.3.0"
  config.default_transport = "JSONRPC"
  
  # Security
  config.force_ssl = true
  config.ssl_verify = true
  
  # Performance
  config.streaming_enabled = true
  config.enable_metrics = true
  config.enable_caching = true
  
  # Storage
  config.storage_backend = :database  # or :redis for distributed
  config.database_url = ENV['DATABASE_URL']
  config.redis_url = ENV['REDIS_URL']
  
  # Logging
  config.log_level = :info
  config.structured_logging = true
  config.log_format = :json
  
  # Rate limiting
  config.rate_limit_enabled = true
  config.rate_limit_requests = 1000
  config.rate_limit_window = 60
  
  # Timeouts
  config.default_timeout = 30
  config.connect_timeout = 10
  
  # Background jobs
  config.background_job_adapter = :sidekiq
end
```

### Environment Variables

```bash
# .env.production
A2A_PROTOCOL_VERSION=0.3.0
A2A_LOG_LEVEL=info
A2A_FORCE_SSL=true
A2A_ENABLE_METRICS=true
A2A_STORAGE_BACKEND=database
A2A_RATE_LIMIT_ENABLED=true
A2A_RATE_LIMIT_REQUESTS=1000

# Database
DATABASE_URL=postgresql://user:password@host:5432/database

# Redis
REDIS_URL=redis://host:6379/0

# Authentication
JWT_SECRET=your-production-jwt-secret
API_KEYS=key1,key2,key3

# External services
WEATHER_API_KEY=your-weather-api-key
WEATHER_API_URL=https://api.weather.com

# Monitoring
PROMETHEUS_ENABLED=true
STATSD_HOST=localhost
STATSD_PORT=8125

# Application
RAILS_ENV=production
RACK_ENV=production
PORT=3000
WEB_CONCURRENCY=2
RAILS_MAX_THREADS=5
```

### Security Checklist

- [ ] Use HTTPS in production (`force_ssl = true`)
- [ ] Verify SSL certificates (`ssl_verify = true`)
- [ ] Use strong JWT secrets
- [ ] Rotate API keys regularly
- [ ] Enable rate limiting
- [ ] Validate all inputs
- [ ] Use secure headers
- [ ] Keep dependencies updated
- [ ] Enable audit logging
- [ ] Use least privilege access

## Docker Deployment

### Dockerfile for Rails Application

```dockerfile
# Dockerfile
FROM ruby:3.2-alpine AS builder

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    postgresql-dev \
    git \
    nodejs \
    yarn

WORKDIR /app

# Copy Gemfile and install gems
COPY Gemfile Gemfile.lock ./
RUN bundle config --global frozen 1 && \
    bundle install --deployment --without development test

# Copy package.json and install node modules
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile --production

# Copy application code
COPY . .

# Precompile assets (Rails)
RUN bundle exec rails assets:precompile

# Production image
FROM ruby:3.2-alpine

# Install runtime dependencies
RUN apk add --no-cache \
    postgresql-client \
    tzdata \
    curl

# Create app user
RUN addgroup -g 1000 -S app && \
    adduser -u 1000 -S app -G app

WORKDIR /app

# Copy built application
COPY --from=builder --chown=app:app /app .

# Switch to app user
USER app

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:3000/a2a/health || exit 1

# Start application
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
```

### Dockerfile for Sinatra Application

```dockerfile
# Dockerfile
FROM ruby:3.2-alpine

# Install dependencies
RUN apk add --no-cache \
    build-base \
    curl

WORKDIR /app

# Copy Gemfile
COPY Gemfile Gemfile.lock ./
RUN bundle install --deployment --without development test

# Copy application
COPY . .

# Create non-root user
RUN adduser -D -s /bin/sh app
USER app

# Expose port
EXPOSE 4567

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:4567/a2a/health || exit 1

# Start application
CMD ["bundle", "exec", "ruby", "app.rb", "-o", "0.0.0.0"]
```

### Docker Compose

```yaml
# docker-compose.yml
version: '3.8'

services:
  app:
    build: .
    ports:
      - "3000:3000"
    environment:
      - DATABASE_URL=postgresql://postgres:password@db:5432/a2a_production
      - REDIS_URL=redis://redis:6379/0
      - RAILS_ENV=production
      - A2A_STORAGE_BACKEND=database
      - A2A_ENABLE_METRICS=true
    depends_on:
      - db
      - redis
    volumes:
      - ./log:/app/log
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/a2a/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  db:
    image: postgres:15-alpine
    environment:
      - POSTGRES_DB=a2a_production
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=password
    volumes:
      - postgres_data:/var/lib/postgresql/data
    restart: unless-stopped

  redis:
    image: redis:7-alpine
    volumes:
      - redis_data:/data
    restart: unless-stopped

  sidekiq:
    build: .
    command: bundle exec sidekiq
    environment:
      - DATABASE_URL=postgresql://postgres:password@db:5432/a2a_production
      - REDIS_URL=redis://redis:6379/0
      - RAILS_ENV=production
    depends_on:
      - db
      - redis
    volumes:
      - ./log:/app/log
    restart: unless-stopped

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
      - ./ssl:/etc/nginx/ssl
    depends_on:
      - app
    restart: unless-stopped

volumes:
  postgres_data:
  redis_data:
```

### Nginx Configuration

```nginx
# nginx.conf
events {
    worker_connections 1024;
}

http {
    upstream app {
        server app:3000;
    }

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;

    server {
        listen 80;
        server_name your-domain.com;
        return 301 https://$server_name$request_uri;
    }

    server {
        listen 443 ssl http2;
        server_name your-domain.com;

        # SSL configuration
        ssl_certificate /etc/nginx/ssl/cert.pem;
        ssl_certificate_key /etc/nginx/ssl/key.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512;

        # Security headers
        add_header X-Frame-Options DENY;
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";

        # A2A endpoints
        location /a2a/ {
            limit_req zone=api burst=20 nodelay;
            
            proxy_pass http://app;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # WebSocket support for streaming
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            
            # Timeouts
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
        }

        # Health check (no rate limiting)
        location /a2a/health {
            proxy_pass http://app;
            proxy_set_header Host $host;
        }

        # Metrics (restrict access)
        location /a2a/metrics {
            allow 10.0.0.0/8;
            allow 172.16.0.0/12;
            allow 192.168.0.0/16;
            deny all;
            
            proxy_pass http://app;
            proxy_set_header Host $host;
        }
    }
}
```

## Kubernetes Deployment

### Deployment Manifest

```yaml
# k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: a2a-weather-agent
  labels:
    app: a2a-weather-agent
spec:
  replicas: 3
  selector:
    matchLabels:
      app: a2a-weather-agent
  template:
    metadata:
      labels:
        app: a2a-weather-agent
    spec:
      containers:
      - name: app
        image: your-registry/a2a-weather-agent:latest
        ports:
        - containerPort: 3000
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: a2a-secrets
              key: database-url
        - name: REDIS_URL
          valueFrom:
            secretKeyRef:
              name: a2a-secrets
              key: redis-url
        - name: JWT_SECRET
          valueFrom:
            secretKeyRef:
              name: a2a-secrets
              key: jwt-secret
        - name: RAILS_ENV
          value: "production"
        - name: A2A_STORAGE_BACKEND
          value: "database"
        - name: A2A_ENABLE_METRICS
          value: "true"
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /a2a/health
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /a2a/health
            port: 3000
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
        volumeMounts:
        - name: logs
          mountPath: /app/log
      volumes:
      - name: logs
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: a2a-weather-agent-service
spec:
  selector:
    app: a2a-weather-agent
  ports:
  - port: 80
    targetPort: 3000
    protocol: TCP
  type: ClusterIP
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: a2a-weather-agent-ingress
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/rate-limit: "100"
    nginx.ingress.kubernetes.io/rate-limit-window: "1m"
spec:
  tls:
  - hosts:
    - weather-agent.your-domain.com
    secretName: a2a-weather-agent-tls
  rules:
  - host: weather-agent.your-domain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: a2a-weather-agent-service
            port:
              number: 80
```

### ConfigMap and Secrets

```yaml
# k8s/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: a2a-config
data:
  A2A_PROTOCOL_VERSION: "0.3.0"
  A2A_LOG_LEVEL: "info"
  A2A_FORCE_SSL: "true"
  A2A_ENABLE_METRICS: "true"
  A2A_RATE_LIMIT_ENABLED: "true"
  A2A_RATE_LIMIT_REQUESTS: "1000"
---
apiVersion: v1
kind: Secret
metadata:
  name: a2a-secrets
type: Opaque
data:
  database-url: <base64-encoded-database-url>
  redis-url: <base64-encoded-redis-url>
  jwt-secret: <base64-encoded-jwt-secret>
  weather-api-key: <base64-encoded-weather-api-key>
```

### Horizontal Pod Autoscaler

```yaml
# k8s/hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: a2a-weather-agent-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: a2a-weather-agent
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

### Background Jobs Deployment

```yaml
# k8s/sidekiq-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: a2a-sidekiq
  labels:
    app: a2a-sidekiq
spec:
  replicas: 2
  selector:
    matchLabels:
      app: a2a-sidekiq
  template:
    metadata:
      labels:
        app: a2a-sidekiq
    spec:
      containers:
      - name: sidekiq
        image: your-registry/a2a-weather-agent:latest
        command: ["bundle", "exec", "sidekiq"]
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: a2a-secrets
              key: database-url
        - name: REDIS_URL
          valueFrom:
            secretKeyRef:
              name: a2a-secrets
              key: redis-url
        - name: RAILS_ENV
          value: "production"
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
```

## Heroku Deployment

### Procfile

```
# Procfile
web: bundle exec puma -C config/puma.rb
worker: bundle exec sidekiq
release: bundle exec rails db:migrate
```

### Heroku Configuration

```bash
# Create Heroku app
heroku create a2a-weather-agent

# Set environment variables
heroku config:set RAILS_ENV=production
heroku config:set A2A_PROTOCOL_VERSION=0.3.0
heroku config:set A2A_LOG_LEVEL=info
heroku config:set A2A_FORCE_SSL=true
heroku config:set A2A_ENABLE_METRICS=true
heroku config:set A2A_STORAGE_BACKEND=database
heroku config:set JWT_SECRET=$(openssl rand -hex 32)

# Add addons
heroku addons:create heroku-postgresql:standard-0
heroku addons:create heroku-redis:premium-0
heroku addons:create papertrail:choklad

# Deploy
git push heroku main

# Scale workers
heroku ps:scale web=2 worker=1

# Run migrations
heroku run rails db:migrate

# Check logs
heroku logs --tail
```

### Heroku-specific Configuration

```ruby
# config/environments/production.rb (Heroku-specific)
Rails.application.configure do
  # Heroku-specific settings
  config.force_ssl = true
  config.log_level = :info
  config.log_tags = [:request_id]
  
  # A2A configuration for Heroku
  config.after_initialize do
    A2A.configure do |a2a_config|
      a2a_config.storage_backend = :database
      a2a_config.redis_url = ENV['REDIS_URL']
      a2a_config.log_level = :info
      a2a_config.enable_metrics = true
      
      # Heroku-specific timeouts
      a2a_config.default_timeout = 25  # Heroku has 30s timeout
      a2a_config.connect_timeout = 5
    end
  end
end
```

## AWS Deployment

### Elastic Beanstalk

```yaml
# .ebextensions/01_packages.config
packages:
  yum:
    git: []
    postgresql-devel: []

# .ebextensions/02_ruby.config
option_settings:
  aws:elasticbeanstalk:application:environment:
    RAILS_ENV: production
    A2A_PROTOCOL_VERSION: "0.3.0"
    A2A_LOG_LEVEL: info
    A2A_FORCE_SSL: true
    A2A_ENABLE_METRICS: true
    A2A_STORAGE_BACKEND: database
  aws:elasticbeanstalk:container:ruby:
    RubyVersion: "3.2"
  aws:autoscaling:launchconfiguration:
    InstanceType: t3.medium
  aws:autoscaling:asg:
    MinSize: 2
    MaxSize: 10
  aws:elasticbeanstalk:environment:
    LoadBalancerType: application
```

### ECS Deployment

```json
{
  "family": "a2a-weather-agent",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::account:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::account:role/ecsTaskRole",
  "containerDefinitions": [
    {
      "name": "a2a-weather-agent",
      "image": "your-account.dkr.ecr.region.amazonaws.com/a2a-weather-agent:latest",
      "portMappings": [
        {
          "containerPort": 3000,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "RAILS_ENV",
          "value": "production"
        },
        {
          "name": "A2A_STORAGE_BACKEND",
          "value": "database"
        }
      ],
      "secrets": [
        {
          "name": "DATABASE_URL",
          "valueFrom": "arn:aws:secretsmanager:region:account:secret:a2a/database-url"
        },
        {
          "name": "JWT_SECRET",
          "valueFrom": "arn:aws:secretsmanager:region:account:secret:a2a/jwt-secret"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/a2a-weather-agent",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "healthCheck": {
        "command": [
          "CMD-SHELL",
          "curl -f http://localhost:3000/a2a/health || exit 1"
        ],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
```

### Lambda Deployment (Serverless)

```ruby
# app.rb (Lambda-compatible)
require 'json'
require 'aws-lambda-ric'
require_relative 'lib/agents/weather_agent'

def lambda_handler(event:, context:)
  begin
    # Parse API Gateway event
    body = event['body']
    body = JSON.parse(body) if body.is_a?(String)
    
    # Handle A2A request
    json_rpc_request = A2A::Protocol::JsonRpc.parse_request(body.to_json)
    
    agent = WeatherAgent.new
    response = agent.handle_a2a_request(json_rpc_request)
    
    {
      statusCode: 200,
      headers: {
        'Content-Type' => 'application/json',
        'Access-Control-Allow-Origin' => '*'
      },
      body: response.to_json
    }
  rescue A2A::Errors::A2AError => e
    {
      statusCode: 400,
      headers: { 'Content-Type' => 'application/json' },
      body: e.to_json_rpc_error.to_json
    }
  rescue => e
    {
      statusCode: 500,
      headers: { 'Content-Type' => 'application/json' },
      body: {
        jsonrpc: "2.0",
        error: { code: -32603, message: "Internal error" },
        id: nil
      }.to_json
    }
  end
end
```

## Monitoring and Logging

### Prometheus Metrics

```ruby
# config/initializers/prometheus.rb
require 'prometheus/client'
require 'prometheus/client/rack/collector'
require 'prometheus/client/rack/exporter'

# Create metrics
A2A_REQUEST_COUNTER = Prometheus::Client::Counter.new(
  :a2a_requests_total,
  docstring: 'Total A2A requests',
  labels: [:method, :status]
)

A2A_REQUEST_DURATION = Prometheus::Client::Histogram.new(
  :a2a_request_duration_seconds,
  docstring: 'A2A request duration',
  labels: [:method]
)

A2A_ACTIVE_TASKS = Prometheus::Client::Gauge.new(
  :a2a_active_tasks,
  docstring: 'Number of active A2A tasks'
)

# Register metrics
Prometheus::Client.registry.register(A2A_REQUEST_COUNTER)
Prometheus::Client.registry.register(A2A_REQUEST_DURATION)
Prometheus::Client.registry.register(A2A_ACTIVE_TASKS)

# Add middleware (Rails)
Rails.application.middleware.use Prometheus::Client::Rack::Collector
Rails.application.middleware.use Prometheus::Client::Rack::Exporter
```

### Structured Logging

```ruby
# config/initializers/logging.rb
require 'logger'
require 'json'

class StructuredLogger < Logger
  def add(severity, message = nil, progname = nil)
    return true if @logdev.nil? or severity < level
    
    log_entry = {
      timestamp: Time.now.utc.iso8601,
      level: format_severity(severity),
      message: message,
      progname: progname,
      pid: Process.pid,
      thread: Thread.current.object_id
    }
    
    # Add request context if available
    if defined?(RequestStore) && RequestStore[:request_id]
      log_entry[:request_id] = RequestStore[:request_id]
    end
    
    @logdev.write(log_entry.to_json + "\n")
    true
  end
end

# Configure A2A logging
A2A.configure do |config|
  config.logger = StructuredLogger.new(STDOUT)
  config.structured_logging = true
end
```

### Health Checks

```ruby
# lib/health_checker.rb
class HealthChecker
  def self.check
    checks = {
      database: check_database,
      redis: check_redis,
      external_apis: check_external_apis,
      a2a_service: check_a2a_service
    }
    
    overall_healthy = checks.values.all? { |check| check[:healthy] }
    
    {
      status: overall_healthy ? 'healthy' : 'unhealthy',
      timestamp: Time.now.utc.iso8601,
      checks: checks,
      version: A2A::VERSION
    }
  end
  
  private
  
  def self.check_database
    ActiveRecord::Base.connection.execute('SELECT 1')
    { healthy: true, response_time_ms: measure_time { ActiveRecord::Base.connection.execute('SELECT 1') } }
  rescue => e
    { healthy: false, error: e.message }
  end
  
  def self.check_redis
    Redis.current.ping
    { healthy: true, response_time_ms: measure_time { Redis.current.ping } }
  rescue => e
    { healthy: false, error: e.message }
  end
  
  def self.check_external_apis
    # Check weather API
    response = Faraday.get('https://api.weather.com/health')
    { healthy: response.status == 200 }
  rescue => e
    { healthy: false, error: e.message }
  end
  
  def self.check_a2a_service
    task_manager = A2A::Server::TaskManager.new
    test_task = task_manager.create_task(type: 'health_check')
    task_manager.get_task(test_task.id)
    { healthy: true }
  rescue => e
    { healthy: false, error: e.message }
  end
  
  def self.measure_time
    start_time = Time.now
    yield
    ((Time.now - start_time) * 1000).round(2)
  end
end
```

## Security Considerations

### SSL/TLS Configuration

```ruby
# config/initializers/ssl.rb
Rails.application.configure do
  # Force SSL in production
  config.force_ssl = true
  
  # HSTS headers
  config.ssl_options = {
    hsts: {
      expires: 1.year,
      subdomains: true,
      preload: true
    }
  }
end

# A2A SSL configuration
A2A.configure do |config|
  config.force_ssl = Rails.env.production?
  config.ssl_verify = true
  
  # Custom SSL options for client connections
  config.ssl_options = {
    verify_mode: OpenSSL::SSL::VERIFY_PEER,
    ca_file: '/etc/ssl/certs/ca-certificates.crt'
  }
end
```

### Authentication Security

```ruby
# lib/security/jwt_validator.rb
class JWTValidator
  def self.validate(token)
    begin
      payload = JWT.decode(
        token,
        Rails.application.secret_key_base,
        true,
        {
          algorithm: 'HS256',
          verify_expiration: true,
          verify_iat: true,
          verify_iss: true,
          iss: 'your-app'
        }
      )
      
      payload[0]
    rescue JWT::ExpiredSignature
      raise A2A::Errors::AuthenticationError, 'Token expired'
    rescue JWT::InvalidIssuerError
      raise A2A::Errors::AuthenticationError, 'Invalid token issuer'
    rescue JWT::DecodeError => e
      raise A2A::Errors::AuthenticationError, "Invalid token: #{e.message}"
    end
  end
end
```

### Input Validation

```ruby
# lib/validators/a2a_validator.rb
class A2AValidator
  def self.validate_message(message)
    errors = []
    
    # Required fields
    errors << "message_id is required" unless message[:message_id]
    errors << "role is required" unless message[:role]
    errors << "parts is required" unless message[:parts]
    
    # Role validation
    unless %w[user agent].include?(message[:role])
      errors << "role must be 'user' or 'agent'"
    end
    
    # Parts validation
    if message[:parts]
      message[:parts].each_with_index do |part, index|
        part_errors = validate_part(part)
        errors.concat(part_errors.map { |e| "parts[#{index}]: #{e}" })
      end
    end
    
    raise A2A::Errors::InvalidParams, errors.join(', ') unless errors.empty?
  end
  
  private
  
  def self.validate_part(part)
    errors = []
    
    errors << "kind is required" unless part[:kind]
    
    case part[:kind]
    when 'text'
      errors << "text is required for text parts" unless part[:text]
    when 'file'
      errors << "file is required for file parts" unless part[:file]
    when 'data'
      errors << "data is required for data parts" unless part[:data]
    else
      errors << "invalid part kind: #{part[:kind]}"
    end
    
    errors
  end
end
```

## Performance Optimization

### Connection Pooling

```ruby
# config/initializers/connection_pool.rb
require 'connection_pool'

# HTTP connection pool
HTTP_POOL = ConnectionPool.new(size: 25, timeout: 5) do
  Faraday.new do |conn|
    conn.adapter :net_http_persistent
    conn.options.timeout = 30
    conn.options.open_timeout = 10
  end
end

# Redis connection pool
REDIS_POOL = ConnectionPool.new(size: 25, timeout: 5) do
  Redis.new(url: ENV['REDIS_URL'])
end

# A2A configuration
A2A.configure do |config|
  config.http_pool = HTTP_POOL
  config.redis_pool = REDIS_POOL
end
```

### Caching Strategy

```ruby
# config/initializers/caching.rb
Rails.application.configure do
  # Use Redis for caching
  config.cache_store = :redis_cache_store, {
    url: ENV['REDIS_URL'],
    namespace: 'a2a_cache',
    expires_in: 1.hour
  }
end

# A2A caching
A2A.configure do |config|
  config.enable_caching = true
  config.cache_backend = :rails
  config.cache_ttl = 300  # 5 minutes
end
```

### Database Optimization

```ruby
# config/database.yml
production:
  adapter: postgresql
  url: <%= ENV['DATABASE_URL'] %>
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  timeout: 5000
  prepared_statements: true
  advisory_locks: true
  
  # Connection pooling
  checkout_timeout: 5
  reaping_frequency: 10
  
  # Performance settings
  statement_timeout: 30000
  connect_timeout: 10
```

## Troubleshooting

### Common Issues

#### High Memory Usage

```ruby
# Monitor memory usage
class MemoryMonitor
  def self.check
    memory_usage = `ps -o rss= -p #{Process.pid}`.to_i
    
    if memory_usage > 500_000  # 500MB
      Rails.logger.warn "High memory usage: #{memory_usage}KB"
      
      # Force garbage collection
      GC.start
      
      # Log memory after GC
      new_usage = `ps -o rss= -p #{Process.pid}`.to_i
      Rails.logger.info "Memory after GC: #{new_usage}KB"
    end
    
    memory_usage
  end
end

# Schedule periodic checks
Thread.new do
  loop do
    MemoryMonitor.check
    sleep(60)
  end
end
```

#### Connection Issues

```ruby
# Connection health checker
class ConnectionHealthChecker
  def self.check_and_recover
    begin
      # Test database connection
      ActiveRecord::Base.connection.execute('SELECT 1')
    rescue => e
      Rails.logger.error "Database connection failed: #{e.message}"
      ActiveRecord::Base.connection.reconnect!
    end
    
    begin
      # Test Redis connection
      Redis.current.ping
    rescue => e
      Rails.logger.error "Redis connection failed: #{e.message}"
      Redis.current.reconnect
    end
  end
end
```

#### Performance Issues

```ruby
# Performance monitoring
class PerformanceMonitor
  def self.monitor_request(request_id, &block)
    start_time = Time.current
    start_memory = get_memory_usage
    
    result = yield
    
    duration = Time.current - start_time
    memory_used = get_memory_usage - start_memory
    
    if duration > 5.0  # Log slow requests
      Rails.logger.warn "Slow request #{request_id}: #{duration}s, #{memory_used}KB"
    end
    
    result
  end
  
  private
  
  def self.get_memory_usage
    `ps -o rss= -p #{Process.pid}`.to_i
  end
end
```

### Debugging Tools

```ruby
# Debug middleware
class A2ADebugMiddleware
  def initialize(app)
    @app = app
  end
  
  def call(env)
    if env['PATH_INFO'].start_with?('/a2a/') && Rails.env.development?
      request_id = SecureRandom.uuid
      
      Rails.logger.debug "A2A Request #{request_id}: #{env['REQUEST_METHOD']} #{env['PATH_INFO']}"
      Rails.logger.debug "Headers: #{extract_headers(env)}"
      
      if env['rack.input']
        body = env['rack.input'].read
        env['rack.input'].rewind
        Rails.logger.debug "Body: #{body}"
      end
      
      start_time = Time.current
      response = @app.call(env)
      duration = Time.current - start_time
      
      Rails.logger.debug "A2A Response #{request_id}: #{response[0]} (#{duration}s)"
      
      response
    else
      @app.call(env)
    end
  end
  
  private
  
  def extract_headers(env)
    env.select { |k, v| k.start_with?('HTTP_') }
       .transform_keys { |k| k.sub(/^HTTP_/, '').tr('_', '-') }
  end
end

# Add to middleware stack
Rails.application.middleware.use A2ADebugMiddleware
```

This comprehensive deployment guide covers all aspects of deploying A2A Ruby SDK applications to production environments, from basic configuration to advanced monitoring and troubleshooting.