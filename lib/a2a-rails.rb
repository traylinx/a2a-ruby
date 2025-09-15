# frozen_string_literal: true

# Rails-specific entry point for A2A Ruby SDK
#
# This file should be required in Rails applications that want to use
# A2A integration features.
#
# @example In Gemfile
#   gem 'a2a-ruby', require: 'a2a-rails'
#
# @example In config/application.rb
#   require 'a2a-rails'
#
#   class Application < Rails::Application
#     config.a2a.enabled = true
#   end

# Load the main A2A library first
require_relative "a2a"

# Ensure Rails is available
begin
  require "rails"
rescue LoadError
  raise LoadError, "Rails is required for A2A Rails integration. Add 'rails' to your Gemfile."
end

# Load Rails-specific components
require_relative "a2a/rails/engine"
require_relative "a2a/rails/controller_helpers"
require_relative "a2a/rails/a2a_controller"

# Extend A2A configuration for Rails-specific options
module A2A
  class Configuration
    # Rails integration settings
    attr_accessor :rails_integration, :mount_path, :auto_mount,
                  :middleware_enabled, :webhook_authentication_required

    def initialize
      super

      # Rails-specific defaults
      @rails_integration = false
      @mount_path = "/a2a"
      @auto_mount = true
      @middleware_enabled = true
      @webhook_authentication_required = false
    end
  end
end

# Auto-configure Rails integration if Rails is detected
if defined?(Rails) && Rails.respond_to?(:application) && Rails.application
  A2A.configure do |config|
    config.rails_integration = true
  end
end
