# frozen_string_literal: true

require_relative "agent"
require_relative "a2a_methods"
require_relative "../types"

##
# Example agent implementation demonstrating A2A protocol methods
#
# This class shows how to create an A2A agent that includes the standard
# protocol methods and implements custom message processing logic.
#
module A2A
  module Server
    class ExampleAgent
      include A2A::Server::Agent
      include A2A::Server::A2AMethods

      # Configure the agent
      a2a_config name: "Example A2A Agent",
                 description: "A demonstration agent for the A2A protocol",
                 version: "1.0.0",
                 default_input_modes: ["text"],
                 default_output_modes: ["text"]

      # Define a simple capability
      a2a_capability "echo" do
        method :echo
        description "Echo back the input message"
        input_schema type: "object",
                     properties: { message: { type: "string" } },
                     required: ["message"]
        output_schema type: "object",
                      properties: { echo: { type: "string" } }
        tags %w[utility test]
      end

      # Define a custom method
      a2a_method "echo" do |params, _context|
        message = params["message"]
        { echo: "You said: #{message}" }
      end

      protected

      ##
      # Process message synchronously
      #
      # @param message [A2A::Types::Message] The message to process
      # @param task [A2A::Types::Task] The associated task
      # @param context [A2A::Server::Context] Request context
      # @return [Object] Processing result
      def process_message_sync(message, task, _context)
        # Extract text from message parts
        text_parts = message.parts.select { |part| part.is_a?(A2A::Types::TextPart) }
        text_content = text_parts.map(&:text).join(" ")

        # Simple echo response
        response_message = A2A::Types::Message.new(
          message_id: SecureRandom.uuid,
          role: A2A::Types::ROLE_AGENT,
          parts: [
            A2A::Types::TextPart.new(text: "Echo: #{text_content}")
          ],
          context_id: message.context_id,
          task_id: task.id
        )

        # Add message to task history
        task_manager.add_message(task.id, message)
        task_manager.add_message(task.id, response_message)

        {
          message: response_message.to_h,
          processed_at: Time.now.utc.iso8601
        }
      end

      ##
      # Process message asynchronously
      #
      # @param message [A2A::Types::Message] The message to process
      # @param task [A2A::Types::Task] The associated task
      # @param context [A2A::Server::Context] Request context
      # @return [void]
      def process_message_async(message, task, context)
        # Start background processing
        Thread.new do
          # Simulate some processing time
          sleep 1

          # Process the message
          result = process_message_sync(message, task, context)

          # Update task with result
          task_manager.update_task_status(
            task.id,
            A2A::Types::TaskStatus.new(
              state: A2A::Types::TASK_STATE_COMPLETED,
              result: result,
              updated_at: Time.now.utc.iso8601
            )
          )
        rescue StandardError => e
          # Handle errors
          task_manager.update_task_status(
            task.id,
            A2A::Types::TaskStatus.new(
              state: A2A::Types::TASK_STATE_FAILED,
              error: { message: e.message, type: e.class.name },
              updated_at: Time.now.utc.iso8601
            )
          )
        end
      end

      ##
      # Process message stream
      #
      # @param message [A2A::Types::Message] The message to process
      # @param task [A2A::Types::Task] The associated task
      # @param context [A2A::Server::Context] Request context
      # @yield [response] Yields each response in the stream
      # @return [void]
      def process_message_stream(message, task, _context)
        # Extract text from message parts
        text_parts = message.parts.select { |part| part.is_a?(A2A::Types::TextPart) }
        text_content = text_parts.map(&:text).join(" ")

        # Stream back the message word by word
        words = text_content.split(/\s+/)

        words.each_with_index do |word, index|
          response_message = A2A::Types::Message.new(
            message_id: SecureRandom.uuid,
            role: A2A::Types::ROLE_AGENT,
            parts: [
              A2A::Types::TextPart.new(text: "Word #{index + 1}: #{word}")
            ],
            context_id: message.context_id,
            task_id: task.id
          )

          yield response_message.to_h

          # Small delay between words
          sleep 0.5
        end

        # Final message
        final_message = A2A::Types::Message.new(
          message_id: SecureRandom.uuid,
          role: A2A::Types::ROLE_AGENT,
          parts: [
            A2A::Types::TextPart.new(text: "Streaming complete. Processed #{words.length} words.")
          ],
          context_id: message.context_id,
          task_id: task.id
        )

        yield final_message.to_h
      end

      ##
      # Generate agent card
      #
      # @param context [A2A::Server::Context] Request context
      # @return [A2A::Types::AgentCard] The agent card
      def generate_agent_card(_context)
        A2A::Types::AgentCard.new(
          name: self.class._a2a_config[:name] || "Example Agent",
          description: self.class._a2a_config[:description] || "An example A2A agent",
          version: self.class._a2a_config[:version] || "1.0.0",
          url: "https://example.com/agent",
          preferred_transport: A2A::Types::TRANSPORT_JSONRPC,
          skills: generate_skills_from_capabilities,
          capabilities: generate_capabilities_info,
          default_input_modes: self.class._a2a_config[:default_input_modes] || ["text"],
          default_output_modes: self.class._a2a_config[:default_output_modes] || ["text"],
          additional_interfaces: [
            A2A::Types::AgentInterface.new(
              transport: A2A::Types::TRANSPORT_JSONRPC,
              url: "https://example.com/agent/rpc"
            )
          ],
          supports_authenticated_extended_card: true,
          protocol_version: "1.0"
        )
      end

      ##
      # Generate extended agent card with authentication context
      #
      # @param context [A2A::Server::Context] Request context
      # @return [A2A::Types::AgentCard] The extended agent card
      def generate_extended_agent_card(context)
        # Get base card
        card = generate_agent_card(context)

        # Add authenticated user information if available
        if context.user
          # Modify card based on user context
          # This is where you could add user-specific capabilities or information
          card.instance_variable_set(:@metadata, {
                                       authenticated_user: context.user.to_s,
                                       authentication_time: Time.now.utc.iso8601,
                                       extended_features: %w[user_context personalized_responses]
                                     })
        end

        card
      end

      private

      ##
      # Generate skills from registered capabilities
      #
      # @return [Array<A2A::Types::AgentSkill>] List of skills
      def generate_skills_from_capabilities
        self.class.a2a_capability_registry.all.map do |capability|
          A2A::Types::AgentSkill.new(
            id: capability.name,
            name: capability.name.humanize,
            description: capability.description || "No description available",
            tags: capability.tags || [],
            examples: capability.examples || [],
            input_modes: ["text"],
            output_modes: ["text"]
          )
        end
      end

      ##
      # Generate capabilities information
      #
      # @return [A2A::Types::AgentCapabilities] Capabilities info
      def generate_capabilities_info
        A2A::Types::AgentCapabilities.new(
          streaming: true,
          push_notifications: true,
          state_transition_history: true,
          extensions: []
        )
      end
    end
  end
end
