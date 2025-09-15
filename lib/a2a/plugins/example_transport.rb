# frozen_string_literal: true

##
# Example custom transport plugin
#
# Demonstrates how to create a custom transport plugin
# for the A2A plugin architecture.
#
module A2A
  module Plugins
    class ExampleTransport < A2A::Plugin::TransportPlugin
      # Transport name for identification
      def transport_name
        "EXAMPLE"
      end

      # Send request implementation
      # @param request [Hash] Request data
      # @param **options [Hash] Transport options
      # @return [Hash] Response
      def send_request(request, **_options)
        logger&.info("Sending request via Example Transport: #{request[:method]}")

        # Simulate request processing
        {
          jsonrpc: "2.0",
          result: { message: "Response from Example Transport" },
          id: request[:id]
        }
      end

      # This transport supports streaming
      def supports_streaming?
        true
      end

      # Create streaming connection
      # @param **options [Hash] Connection options
      # @return [Enumerator] Stream enumerator
      def create_stream(**_options)
        Enumerator.new do |yielder|
          5.times do |i|
            yielder << {
              event: "data",
              data: { message: "Stream message #{i + 1}" }
            }
            sleep(0.1) # Simulate streaming delay
          end
        end
      end

      # Register hooks for this plugin
      def register_hooks(plugin_manager)
        plugin_manager.add_hook(A2A::Plugin::Events::BEFORE_REQUEST) do |request|
          logger&.debug("Example Transport: Processing request #{request[:id]}")
          request[:transport_metadata] = { plugin: "example_transport" }
        end

        plugin_manager.add_hook(A2A::Plugin::Events::AFTER_RESPONSE) do |response, request|
          logger&.debug("Example Transport: Processed response for #{request[:id]}")
          response
        end
      end

      private

      def setup
        logger&.info("Example Transport plugin initialized")
      end

      def cleanup
        logger&.info("Example Transport plugin cleaned up")
      end
    end
  end
end
