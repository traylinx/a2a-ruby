# frozen_string_literal: true

require "rails/generators"
require "rails/generators/named_base"

##
# Rails generator for creating A2A agent controllers
#
# This generator creates a new controller with A2A agent functionality,
# including skills, capabilities, and method definitions.
#
# @example
#   rails generate a2a:agent Chat
#   rails generate a2a:agent Weather --skills=forecast,alerts
#   rails generate a2a:agent Assistant --with-authentication --namespace=api/v1
#
module A2A
  module Rails
    module Generators
      class AgentGenerator < Rails::Generators::NamedBase
        source_root File.expand_path("templates", __dir__)

        class_option :skills, type: :array, default: [],
                              desc: "List of skills to generate (e.g., --skills=chat,search)"

        class_option :with_authentication, type: :boolean, default: false,
                                           desc: "Generate authentication-protected methods"

        class_option :namespace, type: :string, default: nil,
                                 desc: "Namespace for the controller (e.g., api/v1)"

        class_option :skip_tests, type: :boolean, default: false,
                                  desc: "Skip generating test files"

        class_option :api_only, type: :boolean, default: false,
                                desc: "Generate API-only controller (inherits from ActionController::API)"

        desc "Generate an A2A agent controller"

        def create_controller
          template "agent_controller.rb", controller_file_path
          say "Created A2A agent controller: #{controller_class_name}", :green
        end

        def create_tests
          return if options[:skip_tests]

          if rspec_available?
            template "agent_controller_spec.rb", spec_file_path
            say "Created RSpec test: #{spec_file_path}", :green
          else
            template "agent_controller_test.rb", test_file_path
            say "Created test: #{test_file_path}", :green
          end
        end

        def create_documentation
          template "agent_readme.md", documentation_file_path
          say "Created documentation: #{documentation_file_path}", :green
        end

        def add_routes
          route_content = generate_route_content

          return unless File.exist?("config/routes.rb")

          inject_into_file "config/routes.rb", after: "Rails.application.routes.draw do\n" do
            route_content
          end
          say "Added routes for #{controller_class_name}", :green
        end

        def show_post_generation_instructions
          say "\n#{'=' * 60}", :green
          say "A2A Agent '#{class_name}' generated successfully!", :green
          say "=" * 60, :green

          say "\nGenerated files:", :yellow
          say "  #{controller_file_path}"
          say "  #{documentation_file_path}"
          say "  #{test_file_path}" unless options[:skip_tests]

          say "\nNext steps:", :yellow
          say "1. Customize the agent skills and methods in #{controller_file_path}"
          say "2. Implement the A2A method handlers"
          say "3. Test your agent using the generated test file"

          say "\nAgent endpoints:", :yellow
          say "  GET  #{agent_card_path} (Agent Card)"
          say "  POST #{rpc_path} (JSON-RPC Methods)"

          if skills.any?
            say "\nGenerated skills:", :yellow
            skills.each do |skill|
              say "  - #{skill.humanize}"
            end
          end

          say "\nFor more information, visit: https://a2a-protocol.org/sdk/ruby/agents/", :blue
        end

        private

        def controller_file_path
          if namespace.present?
            "app/controllers/#{namespace}/#{file_name}_controller.rb"
          else
            "app/controllers/#{file_name}_controller.rb"
          end
        end

        def spec_file_path
          if namespace.present?
            "spec/controllers/#{namespace}/#{file_name}_controller_spec.rb"
          else
            "spec/controllers/#{file_name}_controller_spec.rb"
          end
        end

        def test_file_path
          if namespace.present?
            "test/controllers/#{namespace}/#{file_name}_controller_test.rb"
          else
            "test/controllers/#{file_name}_controller_test.rb"
          end
        end

        def documentation_file_path
          if namespace.present?
            "docs/agents/#{namespace}/#{file_name}.md"
          else
            "docs/agents/#{file_name}.md"
          end
        end

        def controller_class_name
          if namespace.present?
            "#{namespace.camelize}::#{class_name}Controller"
          else
            "#{class_name}Controller"
          end
        end

        def controller_parent_class
          if options[:api_only]
            "ActionController::API"
          else
            "ApplicationController"
          end
        end

        def namespace
          options[:namespace]
        end

        def skills
          @skills ||= options[:skills].map(&:strip).reject(&:empty?)
        end

        def with_authentication?
          options[:with_authentication]
        end

        def generate_route_content
          if namespace.present?
            namespace_parts = namespace.split("/")
            indent = "  " * namespace_parts.length

            route_lines = []

            # Build nested namespace structure
            namespace_parts.each_with_index do |ns, index|
              route_lines << (("  " * index) + "namespace :#{ns} do")
            end

            # Add the actual route
            route_lines << "#{indent}  resources :#{file_name.pluralize}, only: [] do"
            route_lines << "#{indent}    collection do"
            route_lines << "#{indent}      get :agent_card"
            route_lines << "#{indent}      post :rpc"
            route_lines << "#{indent}    end"
            route_lines << "#{indent}  end"

            # Close namespace blocks
            namespace_parts.length.times do |index|
              route_lines << "#{'  ' * (namespace_parts.length - index - 1)}end"
            end

            "\n#{route_lines.join("\n")}\n"
          else
            <<~RUBY

              # #{class_name} A2A Agent routes
              resources :#{file_name.pluralize}, only: [] do
                collection do
                  get :agent_card
                  post :rpc
                end
              end

            RUBY
          end
        end

        def rspec_available?
          File.exist?("spec/spec_helper.rb") || File.exist?("spec/rails_helper.rb")
        end

        def agent_card_path
          if namespace.present?
            "/#{namespace}/#{file_name.pluralize}/agent_card"
          else
            "/#{file_name.pluralize}/agent_card"
          end
        end

        def rpc_path
          if namespace.present?
            "/#{namespace}/#{file_name.pluralize}/rpc"
          else
            "/#{file_name.pluralize}/rpc"
          end
        end

        def authentication_methods
          if with_authentication?
            skills.map { |skill| "#{skill}_secure" }
          else
            []
          end
        end

        def generate_skill_methods
          skills.map do |skill|
            method_name = skill.underscore

            if with_authentication? && authentication_methods.include?("#{skill}_secure")
              <<~RUBY
                # #{skill.humanize} skill method (authenticated)
                a2a_method "#{method_name}" do |params|
                  # TODO: Implement #{skill.humanize.downcase} functionality
                  {
                    skill: "#{skill}",
                    message: "#{skill.humanize} functionality not yet implemented",
                    params: params,
                    user: current_user_info
                  }
                end
              RUBY
            else
              <<~RUBY
                # #{skill.humanize} skill method
                a2a_method "#{method_name}" do |params|
                  # TODO: Implement #{skill.humanize.downcase} functionality
                  {
                    skill: "#{skill}",
                    message: "#{skill.humanize} functionality not yet implemented",
                    params: params
                  }
                end
              RUBY
            end
          end.join("\n\n")
        end

        def generate_skill_definitions
          skills.map do |skill|
            <<~RUBY
              a2a_skill "#{skill}" do |skill|
                skill.description = "#{skill.humanize} functionality"
                skill.tags = ["#{skill}", "generated"]
                skill.examples = [
                  {
                    input: { action: "#{skill}" },
                    output: { result: "#{skill} completed" }
                  }
                ]
              end
            RUBY
          end.join("\n\n")
        end

        def authentication_config
          if with_authentication?
            auth_methods = authentication_methods.map { |m| "\"#{m}\"" }.join(", ")
            <<~RUBY

              # Configure authentication for specific methods
              a2a_authenticate :devise, methods: [#{auth_methods}]
            RUBY
          else
            ""
          end
        end

        def agent_description
          if skills.any?
            "A2A agent that provides #{skills.map(&:humanize).join(', ')} functionality"
          else
            "A2A agent for #{class_name.humanize.downcase} operations"
          end
        end

        def agent_tags
          base_tags = [class_name.underscore, "generated"]
          (base_tags + skills).uniq
        end
      end
    end
  end
end
