# Event System

The A2A Ruby SDK includes a comprehensive event system that enables real-time, asynchronous processing of agent requests and responses. This event-driven architecture allows for streaming responses, task updates, and flexible agent implementations.

## Overview

The event system consists of:

- **Event**: Represents a single event with type, data, and metadata
- **EventQueue**: Manages event publishing and subscription
- **EventConsumer**: Processes events with registered handlers
- **Event Types**: Predefined event types for different scenarios

## Event Types

### Core Event Types

- `task` - Complete task objects
- `message` - Message objects (user or agent messages)
- `task_status_update` - Task status change events
- `task_artifact_update` - Task artifact addition/modification events

### Event Structure

```ruby
event = A2A::Server::Events::Event.new(
  type: "task_status_update",
  data: status_update_object,
  id: "optional-custom-id"  # Auto-generated if not provided
)

# Event properties
event.type        # => "task_status_update"
event.data        # => The event data object
event.timestamp   # => Time when event was created
event.id          # => Unique event identifier
event.task_id     # => Task ID if applicable
event.context_id  # => Context ID if applicable
```

## Event Queue

### In-Memory Event Queue

```ruby
# Create event queue
queue = A2A::Server::Events::InMemoryEventQueue.new

# Publish events
event = A2A::Server::Events::Event.new(
  type: "message",
  data: message_object
)
queue.publish(event)

# Subscribe to events
queue.subscribe do |event|
  puts "Received event: #{event.type}"
  process_event(event)
end

# Subscribe with filtering
queue.subscribe(->(event) { event.task_event? }) do |event|
  puts "Task-related event: #{event.type}"
end

# Clean up
queue.close
```

### Custom Event Queue Implementation

```ruby
class RedisEventQueue < A2A::Server::Events::EventQueue
  def initialize(redis_client)
    @redis = redis_client
    @subscribers = []
  end
  
  def publish(event)
    @redis.publish("a2a_events", event.to_h.to_json)
  end
  
  def subscribe(filter = nil)
    # Implementation for Redis pub/sub
    @redis.subscribe("a2a_events") do |on|
      on.message do |channel, message|
        event_data = JSON.parse(message)
        event = A2A::Server::Events::Event.new(**event_data.symbolize_keys)
        
        next if filter && !filter.call(event)
        
        yield event if block_given?
      end
    end
  end
  
  def close
    @redis.unsubscribe("a2a_events")
  end
  
  def closed?
    !@redis.connected?
  end
end
```

## Event Consumer

The EventConsumer provides a higher-level interface for processing events:

```ruby
# Create consumer
consumer = A2A::Server::Events::EventConsumer.new(event_queue)

# Register handlers for specific event types
consumer.register_handler("task") do |event|
  task = event.data
  puts "Task received: #{task.id}"
  
  # Save to database
  TaskStore.save(task)
end

consumer.register_handler("task_status_update") do |event|
  status_update = event.data
  puts "Task #{status_update.task_id} status: #{status_update.status.state}"
  
  # Update task in database
  TaskStore.update_status(status_update.task_id, status_update.status)
  
  # Send notifications
  NotificationService.notify_status_change(status_update)
end

consumer.register_handler("message") do |event|
  message = event.data
  puts "Message: #{message.parts.first.text}"
  
  # Process message
  MessageProcessor.process(message)
end

# Start consuming events
consumer.start

# Stop consuming
consumer.stop
```

## Event Filtering

### Basic Filtering

```ruby
# Filter by event type
task_filter = ->(event) { event.task_event? }
message_filter = ->(event) { event.message_event? }

# Filter by task ID
task_id_filter = ->(event) { event.task_id == "specific-task-id" }

# Filter by context ID
context_filter = ->(event) { event.context_id == "specific-context-id" }

# Combine filters
combined_filter = ->(event) {
  event.task_event? && event.task_id == "task-123"
}

queue.subscribe(combined_filter) do |event|
  # Only receives task events for task-123
end
```

### Advanced Filtering

```ruby
class EventFilter
  def initialize(criteria)
    @criteria = criteria
  end
  
  def call(event)
    @criteria.all? { |key, value| matches?(event, key, value) }
  end
  
  private
  
  def matches?(event, key, value)
    case key
    when :type
      event.type == value
    when :task_id
      event.task_id == value
    when :context_id
      event.context_id == value
    when :after
      event.timestamp > value
    when :user_id
      event.data.respond_to?(:user_id) && event.data.user_id == value
    else
      false
    end
  end
end

# Usage
filter = EventFilter.new(
  type: "task_status_update",
  task_id: "task-123",
  after: 1.hour.ago
)

queue.subscribe(filter) do |event|
  # Process filtered events
end
```

## Integration with Agent Executors

Agent executors use the event system to communicate results:

```ruby
class StreamingAgentExecutor < A2A::Server::AgentExecution::AgentExecutor
  def execute(context, event_queue)
    # Create task
    task = create_task(context)
    
    # Publish initial task
    publish_task(event_queue, task)
    
    # Publish status updates
    publish_task_status_update(
      event_queue,
      task.id,
      task.context_id,
      working_status
    )
    
    # Process and publish streaming results
    process_streaming(context.message, event_queue, task)
    
    # Publish completion
    publish_task_status_update(
      event_queue,
      task.id,
      task.context_id,
      completed_status
    )
  end
  
  private
  
  def process_streaming(message, event_queue, task)
    words = message.parts.first.text.split
    
    words.each do |word|
      # Create partial response
      response = A2A::Types::Message.new(
        message_id: SecureRandom.uuid,
        context_id: task.context_id,
        role: "assistant",
        parts: [A2A::Types::TextPart.new(text: word)]
      )
      
      # Publish message event
      publish_message(event_queue, response)
      
      sleep 0.1 # Simulate processing delay
    end
  end
end
```

## Event Persistence

### Database Event Store

```ruby
class DatabaseEventStore
  def initialize(db_connection)
    @db = db_connection
  end
  
  def store_event(event)
    @db.execute(
      "INSERT INTO events (id, type, data, timestamp, task_id, context_id) VALUES (?, ?, ?, ?, ?, ?)",
      event.id,
      event.type,
      event.data.to_json,
      event.timestamp,
      event.task_id,
      event.context_id
    )
  end
  
  def get_events(task_id: nil, context_id: nil, after: nil)
    conditions = []
    params = []
    
    if task_id
      conditions << "task_id = ?"
      params << task_id
    end
    
    if context_id
      conditions << "context_id = ?"
      params << context_id
    end
    
    if after
      conditions << "timestamp > ?"
      params << after
    end
    
    where_clause = conditions.empty? ? "" : "WHERE #{conditions.join(' AND ')}"
    
    @db.execute("SELECT * FROM events #{where_clause} ORDER BY timestamp", *params)
  end
end

# Usage with event consumer
event_store = DatabaseEventStore.new(db_connection)

consumer.register_handler("task") do |event|
  event_store.store_event(event)
end
```

## Real-time Notifications

### WebSocket Integration

```ruby
class WebSocketEventBroadcaster
  def initialize(websocket_server)
    @ws_server = websocket_server
    @client_subscriptions = {}
  end
  
  def subscribe_client(client_id, websocket, filters = {})
    @client_subscriptions[client_id] = {
      websocket: websocket,
      filters: filters
    }
  end
  
  def broadcast_event(event)
    @client_subscriptions.each do |client_id, subscription|
      next unless event_matches_filters?(event, subscription[:filters])
      
      begin
        subscription[:websocket].send(event.to_h.to_json)
      rescue => e
        # Remove disconnected clients
        @client_subscriptions.delete(client_id)
      end
    end
  end
  
  private
  
  def event_matches_filters?(event, filters)
    return true if filters.empty?
    
    filters.all? do |key, value|
      case key
      when :task_id
        event.task_id == value
      when :context_id
        event.context_id == value
      when :event_types
        value.include?(event.type)
      else
        true
      end
    end
  end
end

# Integration
broadcaster = WebSocketEventBroadcaster.new(ws_server)

consumer.register_handler("task_status_update") do |event|
  broadcaster.broadcast_event(event)
end
```

## Testing Events

### Testing Event Publishing

```ruby
RSpec.describe "Event Publishing" do
  let(:event_queue) { A2A::Server::Events::InMemoryEventQueue.new }
  let(:executor) { MyAgentExecutor.new }
  
  it "publishes task events" do
    events = []
    event_queue.subscribe { |event| events << event }
    
    context = create_test_context
    executor.execute(context, event_queue)
    
    task_events = events.select { |e| e.type == "task" }
    expect(task_events).not_to be_empty
    
    status_events = events.select { |e| e.type == "task_status_update" }
    expect(status_events.map(&:data).map(&:status).map(&:state))
      .to include("working", "completed")
  end
end
```

### Testing Event Consumption

```ruby
RSpec.describe "Event Consumption" do
  let(:event_queue) { A2A::Server::Events::InMemoryEventQueue.new }
  let(:consumer) { A2A::Server::Events::EventConsumer.new(event_queue) }
  
  it "processes events with handlers" do
    processed_events = []
    
    consumer.register_handler("test") do |event|
      processed_events << event
    end
    
    consumer.start
    
    # Publish test event
    test_event = A2A::Server::Events::Event.new(
      type: "test",
      data: { message: "test data" }
    )
    event_queue.publish(test_event)
    
    # Wait for processing
    sleep 0.1
    
    expect(processed_events).to include(test_event)
    
    consumer.stop
  end
end
```

## Performance Considerations

1. **Queue Size**: Monitor queue size to prevent memory issues
2. **Event Filtering**: Use efficient filters to reduce processing overhead
3. **Batch Processing**: Consider batching events for high-throughput scenarios
4. **Persistence**: Choose appropriate persistence strategies based on requirements
5. **Error Handling**: Implement robust error handling to prevent event loss

## Best Practices

1. **Event Granularity**: Balance between too many small events and too few large events
2. **Event Ordering**: Consider event ordering requirements for your use case
3. **Error Recovery**: Implement retry mechanisms for failed event processing
4. **Monitoring**: Monitor event queue health and processing metrics
5. **Testing**: Thoroughly test event flows in your application
6. **Documentation**: Document your custom event types and their expected data structures

The event system provides a powerful foundation for building responsive, real-time A2A agents while maintaining clean separation of concerns and enabling sophisticated processing workflows.

## Complete Examples

For complete working examples of event-driven agents, see the [A2A Ruby Samples Repository](https://github.com/a2aproject/a2a-ruby-samples), which includes:

- **Streaming Chat Agent** - Real-time event processing with Server-Sent Events
- **File Processing Agent** - Background job processing with progress events
- **Multi-Agent Client** - Event orchestration across multiple agents
- **Task Management Examples** - Complete task lifecycle event handling