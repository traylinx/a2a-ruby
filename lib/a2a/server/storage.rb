# frozen_string_literal: true

require_relative "storage/base"
require_relative "storage/memory"

# Optional storage backends (only loaded if dependencies are available)
begin
  require_relative "storage/database"
rescue LoadError
  # ActiveRecord not available
end

begin
  require_relative "storage/redis"
rescue LoadError
  # Redis not available
end

##
# Storage backends for task persistence
#
# This module provides different storage implementations for persisting
# tasks and related data. The storage layer is abstracted to allow
# for different backends (memory, database, Redis, etc.).
#
module A2A
  module Server
    module Storage
      # Storage backend types
      TYPE_MEMORY = "memory"
      TYPE_DATABASE = "database"
      TYPE_REDIS = "redis"

      # Valid storage types
      VALID_TYPES = [TYPE_MEMORY, TYPE_DATABASE, TYPE_REDIS].freeze
    end
  end
end
