# Agent Execution Framework

The A2A Ruby SDK provides a powerful agent execution framework that allows you to create custom agents with sophisticated processing logic. This framework is event-driven and supports both synchronous and streaming responses.

## Overview

The agent execution framework consists of several key components:

- **AgentExecutor**: Abstract base class for implementing agent logic
- **RequestContext**: Contains all information needed to process a request
- **EventQueue**: Manages event publishing and consumption
- **DefaultRequestHandler**: Integrates everything together

## Creating Custom Agent Executors

### Basic Agent Executor

```ruby
class MyAgentExecutor < A2A::Server::AgentExecution::SimpleAgentExecutor
  def process_message(message, task, context)
    # Extract text from message parts
    text_parts = message.parts.select { |part| part.is_a?(A2A::Types::TextPart) }
    input_text = text_parts.map(&:text).join(" ")
    
    # Process the input
    response_text = generate_response(input_text)
    
    # Create response message
    response_message = A2A::Types::Message.new(
      message_id: SecureRandom.uuid,
      context_id: message.context_id,
      role: "assistant",
      parts: [A2A::Types::TextPart.new(text: response_text)]
    )
    
    # Return result
    {
      message: response_message.to_h,
      processed_input: input_text,
      timestamp: Time.now.utc.iso8601
    }
  end
  
  private
  
  def generate_response(input)
    # Your custom logic here
    "I received: #{input}"
  end
end
```

### Advanced Agent Executor with Streaming

```ruby
class StreamingAgentExecutor < A2A::Server::AgentExecution::AgentExecutor
  def execute(context, event_queue)
    # Create or get task
    task = ensure_task(context)
    publish_task(event_queue, task)
    
    # Update to working state
    publish_task_status_update(
      event_queue,
      task.id,
      task.context_id,
      A2A::Types::TaskStatus.new(
        state: A2A::Types::TASK_STATE_WORKING,
        message: "Processing request",
        updated_at: Time.now.utc.iso8601
      )
    )
    
    # Process message with streaming
    if context.message
      process_streaming_message(context.message, task, context, event_queue)
    end
    
    # Complete task
    publish_task_status_update(
      event_queue,
      task.id,
      task.context_id,
      A2A::Types::TaskStatus.new(
        state: A2A::Types::TASK_STATE_COMPLETED,
        message: "Processing complete",
        updated_at: Time.now.utc.iso8601
      )
    )
  end
  
  def cancel(context, event_queue)
    publish_task_status_update(
      event_queue,
      context.task_id,
      context.context_id,
      A2A::Types::TaskStatus.new(
        state: A2A::Types::TASK_STATE_CANCELED,
        message: "Task canceled",
        updated_at: Time.now.utc.iso8601
      )
    )
  end
  
  private
  
  def process_streaming_message(message, task, context, event_queue)
    text = message.parts.first.text
    words = text.split
    
    words.each_with_index do |word, index|
      # Publish partial response
      partial_message = A2A::Types::Message.new(
        message_id: SecureRandom.uuid,
        context_id: message.context_id,
        role: "assistant",
        parts: [A2A::Types::TextPart.new(text: word)]
      )
      
      publish_message(event_queue, partial_message)
      
      # Simulate processing delay
      sleep 0.1
    end
  end
  
  def ensure_task(context)
    # Create new task if needed
    task_id = context.task_id || SecureRandom.uuid
    context_id = context.context_id || SecureRandom.uuid
    
    A2A::Types::Task.new(
      id: task_id,
      context_id: context_id,
      status: A2A::Types::TaskStatus.new(
        state: A2A::Types::TASK_STATE_SUBMITTED,
        message: "Task created",
        updated_at: Time.now.utc.iso8601
      ),
      history: context.message ? [context.message] : [],
      metadata: {
        created_at: Time.now.utc.iso8601,
        executor: self.class.name
      }
    )
  end
end
```

## Request Context

The `RequestContext` provides all the information needed to process a request:

```ruby
# Access message data
if context.has_message?
  message = context.message
  text = message.parts.first.text
end

# Check if this is a new or continuing task
if context.new_task?
  # Handle new task creation
else
  # Continue existing task
  task_id = context.task_id
end

# Access user information
if context.authenticated?
  user = context.user
  auth_data = context.authentication("oauth2")
end

# Access metadata
custom_data = context.get_metadata(:custom_key)
context.set_metadata(:processed_at, Time.now)
```

## Event System Integration

The agent executor publishes events that are automatically processed:

```ruby
class MyExecutor < A2A::Server::AgentExecution::AgentExecutor
  def execute(context, event_queue)
    # Publish task events
    publish_task(event_queue, task)
    
    # Publish status updates
    publish_task_status_update(event_queue, task_id, context_id, status)
    
    # Publish artifact updates
    publish_task_artifact_update(event_queue, task_id, context_id, artifact)
    
    # Publish messages
    publish_message(event_queue, message)
  end
end
```

## Integration with Request Handler

```ruby
# Create executor
executor = MyAgentExecutor.new

# Create request handler
handler = A2A::Server::DefaultRequestHandler.new(executor)

# Use with server applications
app = A2A::Server::Apps::RackApp.new(
  agent_card: agent_card,
  request_handler: handler
)
```

## Error Handling

```ruby
class RobustAgentExecutor < A2A::Server::AgentExecution::SimpleAgentExecutor
  def process_message(message, task, context)
    begin
      # Your processing logic
      result = complex_processing(message)
      
      # Return successful result
      { result: result, status: "success" }
    rescue StandardError => e
      # Log error
      A2A.logger.error("Processing failed", error: e.message)
      
      # Return error result
      {
        error: {
          message: e.message,
          type: e.class.name
        },
        status: "error"
      }
    end
  end
  
  private
  
  def complex_processing(message)
    # Your complex logic that might fail
    raise "Something went wrong" if message.parts.empty?
    
    "Processed successfully"
  end
end
```

## Best Practices

1. **Keep Executors Focused**: Each executor should handle a specific type of agent logic
2. **Use Events Properly**: Publish appropriate events for task lifecycle management
3. **Handle Errors Gracefully**: Always catch and handle exceptions appropriately
4. **Support Cancellation**: Implement the `cancel` method for long-running tasks
5. **Use Context Effectively**: Leverage the request context for user and metadata access
6. **Test Thoroughly**: Write comprehensive tests for your agent executors

## Testing Agent Executors

```ruby
RSpec.describe MyAgentExecutor do
  let(:executor) { described_class.new }
  let(:event_queue) { A2A::Server::Events::InMemoryEventQueue.new }
  let(:message) { create_test_message("Hello, agent!") }
  let(:context) { create_test_context(message: message) }
  
  describe "#execute" do
    it "processes messages correctly" do
      events = []
      event_queue.subscribe { |event| events << event }
      
      executor.execute(context, event_queue)
      
      expect(events).to include(have_attributes(type: "task"))
      expect(events).to include(have_attributes(type: "task_status_update"))
    end
  end
  
  describe "#cancel" do
    it "cancels tasks properly" do
      events = []
      event_queue.subscribe { |event| events << event }
      
      executor.cancel(context, event_queue)
      
      canceled_event = events.find { |e| e.type == "task_status_update" }
      expect(canceled_event.data.status.state).to eq("canceled")
    end
  end
end
```

This framework provides the flexibility to create sophisticated agents while maintaining consistency with the A2A protocol and ensuring proper integration with the broader SDK ecosystem.

## Complete Examples

For complete working examples of agent executors in action, see the [A2A Ruby Samples Repository](https://github.com/a2aproject/a2a-ruby-samples), which includes:

- **Hello World Agent** - Basic agent executor implementation
- **Dice Agent** - Interactive agent with function calling
- **Weather Agent** - Real-world service integration
- **Rails Integration** - Production Rails applications
- **Streaming Chat Agent** - Real-time communication examples