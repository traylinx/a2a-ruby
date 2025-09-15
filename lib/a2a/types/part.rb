# frozen_string_literal: true

module A2A::Types
  ##
  # Base class for message parts (discriminated union)
  #
  # Parts represent different types of content within a message.
  # This is an abstract base class - use TextPart, FilePart, or DataPart.
  #
  class Part < A2A::Types::BaseModel
    attr_reader :kind, :metadata

    ##
    # Create a part from a hash (factory method)
    #
    # @param hash [Hash] The hash representation
    # @return [Part] The appropriate part subclass instance
    def self.from_h(hash)
      return hash if hash.is_a?(Part) # Already a Part instance
      return nil if hash.nil?

      kind = hash[:kind] || hash["kind"]
      case kind
      when PART_KIND_TEXT
        TextPart.from_h(hash)
      when PART_KIND_FILE
        FilePart.from_h(hash)
      when PART_KIND_DATA
        DataPart.from_h(hash)
      else
        raise ArgumentError, "Unknown part kind: #{kind}"
      end
    end

    protected

    def initialize(kind:, metadata: nil)
      @kind = kind
      @metadata = metadata
      validate!
    end

    private

    def validate!
      validate_required(:kind)
      validate_inclusion(:kind, VALID_PART_KINDS)
    end
  end

  ##
  # Represents a text part in a message
  #
  class TextPart < Part
    attr_reader :text

    ##
    # Initialize a new text part
    #
    # @param text [String] The text content
    # @param metadata [Hash, nil] Additional metadata
    def initialize(text:, metadata: nil)
      @text = text
      super(kind: PART_KIND_TEXT, metadata: metadata)
    end

    ##
    # Create a TextPart from a hash
    #
    # @param hash [Hash] The hash representation
    # @return [TextPart] The new instance
    def self.from_h(hash)
      return hash if hash.is_a?(TextPart)
      return nil if hash.nil?

      # Convert string keys to symbols and snake_case camelCase keys
      normalized_hash = {}
      hash.each do |key, value|
        snake_key = BaseModel.underscore(key.to_s).to_sym
        normalized_hash[snake_key] = value unless snake_key == :kind
      end

      new(**normalized_hash)
    end

    private

    def validate!
      super
      validate_required(:text)
      validate_type(:text, String)
    end
  end

  ##
  # Represents a file part in a message
  #
  class FilePart < Part
    attr_reader :file

    ##
    # Initialize a new file part
    #
    # @param file [FileBase] The file object
    # @param metadata [Hash, nil] Additional metadata
    def initialize(file:, metadata: nil)
      @file = file.is_a?(Hash) ? FileBase.from_h(file) : file
      super(kind: PART_KIND_FILE, metadata: metadata)
    end

    ##
    # Create a FilePart from a hash
    #
    # @param hash [Hash] The hash representation
    # @return [FilePart] The new instance
    def self.from_h(hash)
      return hash if hash.is_a?(FilePart)
      return nil if hash.nil?

      # Convert string keys to symbols and snake_case camelCase keys
      normalized_hash = {}
      hash.each do |key, value|
        snake_key = BaseModel.underscore(key.to_s).to_sym
        normalized_hash[snake_key] = value unless snake_key == :kind
      end

      new(**normalized_hash)
    end

    private

    def validate!
      super
      validate_required(:file)
      validate_type(:file, FileBase)
    end
  end

  ##
  # Represents a data part in a message
  #
  class DataPart < Part
    attr_reader :data

    ##
    # Initialize a new data part
    #
    # @param data [Object] The data content (any JSON-serializable object)
    # @param metadata [Hash, nil] Additional metadata
    def initialize(data:, metadata: nil)
      @data = data
      super(kind: PART_KIND_DATA, metadata: metadata)
    end

    ##
    # Create a DataPart from a hash
    #
    # @param hash [Hash] The hash representation
    # @return [DataPart] The new instance
    def self.from_h(hash)
      return hash if hash.is_a?(DataPart)
      return nil if hash.nil?

      # Convert string keys to symbols and snake_case camelCase keys
      normalized_hash = {}
      hash.each do |key, value|
        snake_key = BaseModel.underscore(key.to_s).to_sym
        normalized_hash[snake_key] = value unless snake_key == :kind
      end

      new(**normalized_hash)
    end

    private

    def validate!
      super
      validate_required(:data)
    end
  end

  ##
  # Base class for file representations
  #
  class FileBase < A2A::Types::BaseModel
    ##
    # Create a file from a hash (factory method)
    #
    # @param hash [Hash] The hash representation
    # @return [FileBase] The appropriate file subclass instance
    def self.from_h(hash)
      return nil if hash.nil?

      if hash.key?(:bytes) || hash.key?("bytes")
        FileWithBytes.from_h(hash)
      elsif hash.key?(:uri) || hash.key?("uri")
        FileWithUri.from_h(hash)
      else
        raise ArgumentError, "File must have either 'bytes' or 'uri'"
      end
    end
  end

  ##
  # Represents a file with base64-encoded bytes
  #
  class FileWithBytes < FileBase
    attr_reader :name, :mime_type, :bytes

    ##
    # Initialize a new file with bytes
    #
    # @param name [String] The file name
    # @param mime_type [String] The MIME type
    # @param bytes [String] Base64-encoded file content
    def initialize(name:, mime_type:, bytes:)
      @name = name
      @mime_type = mime_type
      @bytes = bytes
      validate!
    end

    ##
    # Get the decoded file content
    #
    # @return [String] The decoded binary content
    def content
      require "base64"
      Base64.decode64(@bytes)
    end

    ##
    # Get the file size in bytes
    #
    # @return [Integer] The file size
    def size
      content.bytesize
    end

    private

    def validate!
      validate_required(:name, :mime_type, :bytes)
      validate_type(:name, String)
      validate_type(:mime_type, String)
      validate_type(:bytes, String)
    end
  end

  ##
  # Represents a file with a URI reference
  #
  class FileWithUri < FileBase
    attr_reader :name, :mime_type, :uri

    ##
    # Initialize a new file with URI
    #
    # @param name [String] The file name
    # @param mime_type [String] The MIME type
    # @param uri [String] The file URI
    def initialize(name:, mime_type:, uri:)
      @name = name
      @mime_type = mime_type
      @uri = uri
      validate!
    end

    private

    def validate!
      validate_required(:name, :mime_type, :uri)
      validate_type(:name, String)
      validate_type(:mime_type, String)
      validate_type(:uri, String)

      # Basic URI validation
      begin
        require "uri"
        URI.parse(@uri)
      rescue URI::InvalidURIError
        raise ArgumentError, "Invalid URI: #{@uri}"
      end
    end
  end
end
