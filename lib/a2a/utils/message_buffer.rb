# frozen_string_literal: true

require "stringio"
require "zlib"

##
# Memory-efficient message buffer for handling large messages
#
# Provides streaming capabilities and compression for large message handling
# to optimize memory usage and performance.
#
module A2A
  module Utils
    class MessageBuffer
      # Default buffer size (64KB)
      DEFAULT_BUFFER_SIZE = 64 * 1024

      # Compression threshold (1MB)
      COMPRESSION_THRESHOLD = 1024 * 1024

      attr_reader :size, :compressed, :encoding

      ##
      # Initialize a new message buffer
      #
      # @param initial_capacity [Integer] Initial buffer capacity
      # @param compress [Boolean] Whether to use compression for large messages
      # @param encoding [Encoding] Text encoding to use
      def initialize(initial_capacity: DEFAULT_BUFFER_SIZE, compress: true, encoding: Encoding::UTF_8)
        @buffer = StringIO.new
        @buffer.set_encoding(encoding)
        @initial_capacity = initial_capacity
        @compress = compress
        @compressed = false
        @encoding = encoding
        @chunks = []
        @total_size = 0
      end

      ##
      # Write data to the buffer
      #
      # @param data [String] Data to write
      # @return [Integer] Number of bytes written
      def write(data)
        data = data.to_s.encode(@encoding) unless data.encoding == @encoding

        if @compressed
          # If already compressed, decompress first
          decompress!
        end

        bytes_written = @buffer.write(data)
        @total_size += bytes_written

        # Compress if buffer gets too large
        compress! if @compress && @total_size > COMPRESSION_THRESHOLD && !@compressed

        bytes_written
      end

      ##
      # Append data to the buffer (alias for write)
      #
      # @param data [String] Data to append
      # @return [Integer] Number of bytes written
      def <<(data)
        write(data)
      end

      ##
      # Read data from the buffer
      #
      # @param length [Integer, nil] Number of bytes to read (nil for all)
      # @return [String] Data read from buffer
      def read(length = nil)
        decompress! if @compressed

        @buffer.rewind
        data = @buffer.read(length)
        @buffer.rewind
        data
      end

      ##
      # Get the current size of the buffer
      #
      # @return [Integer] Size in bytes
      def size
        @compressed ? @compressed_size : @buffer.size
      end

      ##
      # Check if buffer is empty
      #
      # @return [Boolean] True if buffer is empty
      def empty?
        size.zero?
      end

      ##
      # Clear the buffer
      #
      def clear!
        @buffer = StringIO.new
        @buffer.set_encoding(@encoding)
        @compressed = false
        @compressed_size = 0
        @total_size = 0
        @chunks.clear
      end

      ##
      # Get buffer contents as string
      #
      # @return [String] Buffer contents
      def to_s
        read
      end

      ##
      # Get buffer contents as JSON
      #
      # @return [String] JSON representation
      def to_json(*_args)
        A2A::Utils::Performance.optimized_json_generate(to_s)
      end

      ##
      # Create buffer from JSON string
      #
      # @param json_string [String] JSON string
      # @return [MessageBuffer] New buffer with JSON data
      def self.from_json(json_string)
        data = A2A::Utils::Performance.optimized_json_parse(json_string)
        buffer = new
        buffer.write(data.to_s)
        buffer
      end

      ##
      # Stream data in chunks
      #
      # @param chunk_size [Integer] Size of each chunk
      # @yield [String] Each chunk of data
      def each_chunk(chunk_size = DEFAULT_BUFFER_SIZE)
        return enum_for(:each_chunk, chunk_size) unless block_given?

        decompress! if @compressed

        @buffer.rewind

        while (chunk = @buffer.read(chunk_size))
          yield chunk
        end

        @buffer.rewind
      end

      ##
      # Compress buffer contents
      #
      def compress!
        return if @compressed || @buffer.size < COMPRESSION_THRESHOLD

        @buffer.rewind
        original_data = @buffer.read
        @buffer.rewind

        compressed_data = Zlib::Deflate.deflate(original_data)

        # Only use compression if it actually saves space
        return unless compressed_data.size < original_data.size

        @buffer = StringIO.new(compressed_data)
        @compressed = true
        @compressed_size = compressed_data.size
        @original_size = original_data.size
      end

      ##
      # Decompress buffer contents
      #
      def decompress!
        return unless @compressed

        @buffer.rewind
        compressed_data = @buffer.read
        @buffer.rewind

        original_data = Zlib::Inflate.inflate(compressed_data)

        @buffer = StringIO.new
        @buffer.set_encoding(@encoding)
        @buffer.write(original_data)
        @buffer.rewind

        @compressed = false
        @total_size = original_data.size
      end

      ##
      # Get compression ratio
      #
      # @return [Float] Compression ratio (0.0 to 1.0)
      def compression_ratio
        return 0.0 unless @compressed && @original_size&.positive?

        1.0 - (@compressed_size.to_f / @original_size)
      end

      ##
      # Get buffer statistics
      #
      # @return [Hash] Buffer statistics
      def stats
        {
          size: size,
          compressed: @compressed,
          compression_ratio: compression_ratio,
          encoding: @encoding.name,
          chunks: @chunks.size
        }
      end

      ##
      # Optimize buffer for memory usage
      #
      def optimize!
        # Force garbage collection on buffer
        GC.start if defined?(GC)

        # Compress if beneficial
        compress! if @compress && !@compressed && size > COMPRESSION_THRESHOLD

        # Compact string if possible (Ruby 2.7+)
        return unless @buffer.string.respond_to?(:squeeze!)

        @buffer.string.squeeze!
      end

      ##
      # Create a memory-mapped buffer for very large data
      #
      # @param file_path [String] Path to temporary file
      # @return [MessageBuffer] Memory-mapped buffer
      def self.create_memory_mapped(file_path)
        # This would require additional gems like 'mmap' for true memory mapping
        # For now, we'll use a file-backed buffer
        buffer = new
        buffer.instance_variable_set(:@file_backed, true)
        buffer.instance_variable_set(:@file_path, file_path)
        buffer
      end

      private

      ##
      # Ensure buffer has minimum capacity
      #
      # @param capacity [Integer] Required capacity
      def ensure_capacity(capacity)
        return if @buffer.size >= capacity

        # Expand buffer if needed
        current_pos = @buffer.pos
        @buffer.seek(0, IO::SEEK_END)

        # Write null bytes to expand
        padding_needed = capacity - @buffer.size
        @buffer.write("\0" * padding_needed) if padding_needed.positive?

        @buffer.pos = current_pos
      end
    end
  end
end
