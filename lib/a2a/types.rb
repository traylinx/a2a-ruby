# frozen_string_literal: true

require_relative "types/base_model"
require_relative "types/agent_card"
require_relative "types/message"
require_relative "types/task"
require_relative "types/part"
require_relative "types/artifact"
require_relative "types/events"
require_relative "types/push_notification"
require_relative "types/security"

##
# Type definitions for the A2A protocol
#
# This module contains all the data types used in the A2A protocol,
# including messages, tasks, agent cards, and various supporting types.
#
module A2A
  module Types
    # Transport protocol constants
    TRANSPORT_JSONRPC = "JSONRPC"
    TRANSPORT_GRPC = "GRPC"
    TRANSPORT_HTTP_JSON = "HTTP+JSON"

    # Valid transport protocols
    VALID_TRANSPORTS = [TRANSPORT_JSONRPC, TRANSPORT_GRPC, TRANSPORT_HTTP_JSON].freeze

    # Message roles
    ROLE_USER = "user"
    ROLE_AGENT = "agent"

    # Valid message roles
    VALID_ROLES = [ROLE_USER, ROLE_AGENT].freeze

    # Task states
    TASK_STATE_SUBMITTED = "submitted"
    TASK_STATE_WORKING = "working"
    TASK_STATE_INPUT_REQUIRED = "input-required"
    TASK_STATE_COMPLETED = "completed"
    TASK_STATE_CANCELED = "canceled"
    TASK_STATE_FAILED = "failed"
    TASK_STATE_REJECTED = "rejected"
    TASK_STATE_AUTH_REQUIRED = "auth-required"
    TASK_STATE_UNKNOWN = "unknown"

    # Valid task states
    VALID_TASK_STATES = [
      TASK_STATE_SUBMITTED,
      TASK_STATE_WORKING,
      TASK_STATE_INPUT_REQUIRED,
      TASK_STATE_COMPLETED,
      TASK_STATE_CANCELED,
      TASK_STATE_FAILED,
      TASK_STATE_REJECTED,
      TASK_STATE_AUTH_REQUIRED,
      TASK_STATE_UNKNOWN
    ].freeze

    # Part kinds
    PART_KIND_TEXT = "text"
    PART_KIND_FILE = "file"
    PART_KIND_DATA = "data"

    # Valid part kinds
    VALID_PART_KINDS = [PART_KIND_TEXT, PART_KIND_FILE, PART_KIND_DATA].freeze

    # Object kinds
    KIND_MESSAGE = "message"
    KIND_TASK = "task"

    # Security scheme types
    SECURITY_TYPE_API_KEY = "apiKey"
    SECURITY_TYPE_HTTP = "http"
    SECURITY_TYPE_OAUTH2 = "oauth2"
    SECURITY_TYPE_OPENID_CONNECT = "openIdConnect"
    SECURITY_TYPE_MUTUAL_TLS = "mutualTLS"

    # Valid security scheme types
    VALID_SECURITY_TYPES = [
      SECURITY_TYPE_API_KEY,
      SECURITY_TYPE_HTTP,
      SECURITY_TYPE_OAUTH2,
      SECURITY_TYPE_OPENID_CONNECT,
      SECURITY_TYPE_MUTUAL_TLS
    ].freeze
  end
end
