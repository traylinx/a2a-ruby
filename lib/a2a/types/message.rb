# frozen_string_literal: true

##
# Represents a message in the A2A protocol
#
# Messages are the primary means of communication between agents and users.
# They contain one or more parts (text, files, or data) and metadata.
#
class A2A::Types::Message < A2A::Types::BaseModel
  attr_reader :message_id, :role, :parts, :context_id, :task_id, :kind,
    :metadata, :extensions, :reference_task_ids

  ##
  # Initialize a new message
  #
  # @param message_id [String] Unique message identifier
  # @param role [String] Message role ("user" or "agent")
  # @param parts [Array<Part>] Message parts
  # @param kind [String] Message kind (always "message")
  # @param context_id [String, nil] Context identifier
  # @param task_id [String, nil] Associated task identifier
  # @param metadata [Hash, nil] Additional metadata
  # @param extensions [Array<Hash>, nil] Protocol extensions
  # @param reference_task_ids [Array<String>, nil] Referenced task IDs
  def initialize(message_id:, role:, parts:, kind: KIND_MESSAGE, context_id: nil,
    task_id: nil, metadata: nil, extensions: nil, reference_task_ids: nil)
    @message_id = message_id
    @role = role
    @parts = parts.map { |p| p.is_a?(Part) ? p : Part.from_h(p) }
    @kind = kind
    @context_id = context_id
    @task_id = task_id
    @metadata = metadata
    @extensions = extensions
    @reference_task_ids = reference_task_ids

    validate!
  end

  ##
  # Get all text content from the message
  #
  # @return [String] Combined text from all text parts
  def text_content
    @parts.select { |p| p.is_a?(TextPart) }
      .map(&:text)
      .join("\n")
  end

  ##
  # Get all file parts from the message
  #
  # @return [Array<FilePart>] All file parts
  def file_parts
    @parts.select { |p| p.is_a?(FilePart) }
  end

  ##
  # Get all data parts from the message
  #
  # @return [Array<DataPart>] All data parts
  def data_parts
    @parts.select { |p| p.is_a?(DataPart) }
  end

  ##
  # Add a part to the message
  #
  # @param part [Part] The part to add
  def add_part(part)
    @parts << part
  end

  ##
  # Check if the message is from a user
  #
  # @return [Boolean] True if the message is from a user
  def from_user?
    @role == ROLE_USER
  end

  ##
  # Check if the message is from an agent
  #
  # @return [Boolean] True if the message is from an agent
  def from_agent?
    @role == ROLE_AGENT
  end

  private

  def validate!
    validate_required(:message_id, :role, :parts, :kind)
    validate_inclusion(:role, VALID_ROLES)
    validate_inclusion(:kind, [KIND_MESSAGE])
    validate_array_type(:parts, Part)

    return unless @parts.empty?

    raise ArgumentError, "Message must have at least one part"
  end
end
