# frozen_string_literal: true

##
# Utility module for Rails detection and compatibility
#
# Provides consistent Rails detection methods that can be used throughout
# the A2A Ruby gem to handle Rails availability gracefully.
#
module A2A
  module Utils
    module RailsDetection
      # Check if Rails is available and properly defined
      # @return [Boolean] true if Rails is available
      def rails_available?
        defined?(::Rails) && ::Rails.respond_to?(:version)
      end

      # Check if Rails version requires validation
      # @return [Boolean] true if Rails version is less than 6.0
      def rails_version_requires_validation?
        return false unless rails_available?

        begin
          ::Rails.version < "6.0"
        rescue StandardError
          # If we can't get the version, assume validation is not required
          false
        end
      end

      # Check if Rails version is supported (6.0+)
      # @return [Boolean] true if Rails version is 6.0 or higher
      def rails_version_supported?
        return false unless rails_available?

        begin
          ::Rails.version >= "6.0"
        rescue StandardError
          false
        end
      end

      # Get Rails logger if available
      # @return [Logger, nil] Rails logger or nil if not available
      def rails_logger
        return nil unless rails_available?
        return nil unless ::Rails.respond_to?(:logger)

        ::Rails.logger
      end

      # Get Rails environment if available
      # @return [String, nil] Rails environment or nil if not available
      def rails_environment
        return nil unless rails_available?
        return nil unless ::Rails.respond_to?(:env)

        ::Rails.env
      end

      # Get Rails application if available
      # @return [Rails::Application, nil] Rails application or nil if not available
      def rails_application
        return nil unless rails_available?
        return nil unless ::Rails.respond_to?(:application)

        ::Rails.application
      end

      # Check if we're in a Rails production environment
      # @return [Boolean] true if in Rails production environment
      def rails_production?
        env = rails_environment
        env && env == "production"
      end

      # Check if we're in a Rails development environment
      # @return [Boolean] true if in Rails development environment
      def rails_development?
        env = rails_environment
        env && env == "development"
      end

      # Get Rails version string if available
      # @return [String, nil] Rails version or nil if not available
      def rails_version
        return nil unless rails_available?

        begin
          ::Rails.version
        rescue StandardError
          nil
        end
      end
    end
  end
end
