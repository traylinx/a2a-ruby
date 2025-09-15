# frozen_string_literal: true

##
# Represents an artifact in the A2A protocol
#
# Artifacts are outputs or intermediate results produced by agents during task execution.
# They can contain multiple parts (text, files, or data) and have associated metadata.
#
module A2A
  module Types
    class Artifact < A2A::Types::BaseModel
      attr_reader :artifact_id, :name, :description, :parts, :metadata, :extensions

      ##
      # Initialize a new artifact
      #
      # @param artifact_id [String] Unique artifact identifier
      # @param parts [Array<Part>] Artifact parts
      # @param name [String, nil] Optional artifact name
      # @param description [String, nil] Optional artifact description
      # @param metadata [Hash, nil] Additional metadata
      # @param extensions [Array<Hash>, nil] Protocol extensions
      def initialize(artifact_id:, parts:, name: nil, description: nil, metadata: nil, extensions: nil)
        @artifact_id = artifact_id
        @parts = parts.map { |p| p.is_a?(Part) ? p : Part.from_h(p) }
        @name = name
        @description = description
        @metadata = metadata
        @extensions = extensions

        validate!
      end

      ##
      # Get all text content from the artifact
      #
      # @return [String] Combined text from all text parts
      def text_content
        @parts.select { |p| p.is_a?(TextPart) }
              .map(&:text)
              .join("\n")
      end

      ##
      # Get all file parts from the artifact
      #
      # @return [Array<FilePart>] All file parts
      def file_parts
        @parts.select { |p| p.is_a?(FilePart) }
      end

      ##
      # Get all data parts from the artifact
      #
      # @return [Array<DataPart>] All data parts
      def data_parts
        @parts.select { |p| p.is_a?(DataPart) }
      end

      ##
      # Add a part to the artifact
      #
      # @param part [Part] The part to add
      def add_part(part)
        @parts << part
      end

      ##
      # Check if the artifact has any content
      #
      # @return [Boolean] True if the artifact has parts
      def has_content?
        !@parts.empty?
      end

      ##
      # Get the total size of all file parts
      #
      # @return [Integer] Total size in bytes
      def total_file_size
        file_parts.sum do |file_part|
          file_part.file.respond_to?(:size) ? file_part.file.size : 0
        end
      end

      private

      def validate!
        validate_required(:artifact_id, :parts)
        validate_type(:artifact_id, String)
        validate_array_type(:parts, Part)

        return unless @parts.empty?

        raise ArgumentError, "Artifact must have at least one part"
      end
    end
  end
end
