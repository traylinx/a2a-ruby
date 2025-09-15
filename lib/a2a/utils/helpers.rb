# frozen_string_literal: true

require "securerandom"
require "digest"
require "base64"

##
# Common utility helper methods
#
# Provides various utility methods for UUID generation, string manipulation,
# encoding/decoding, and other common operations used throughout the A2A gem.
#
module A2A
  module Utils
    module Helpers
      class << self
        ##
        # Generate a UUID
        #
        # @return [String] A new UUID string
        def generate_uuid
          SecureRandom.uuid
        end

        ##
        # Generate a random hex string
        #
        # @param length [Integer] Length of the hex string (default: 16)
        # @return [String] Random hex string
        def generate_hex(length = 16)
          SecureRandom.hex(length)
        end

        ##
        # Generate a secure random token
        #
        # @param length [Integer] Length of the token (default: 32)
        # @return [String] Base64-encoded random token
        def generate_token(length = 32)
          Base64.urlsafe_encode64(SecureRandom.random_bytes(length), padding: false)
        end

        ##
        # Generate a hash of a string
        #
        # @param string [String] String to hash
        # @param algorithm [Symbol] Hash algorithm (:sha256, :sha1, :md5)
        # @return [String] Hex-encoded hash
        def hash_string(string, algorithm: :sha256)
          case algorithm
          when :sha256
            Digest::SHA256.hexdigest(string)
          when :sha1
            Digest::SHA1.hexdigest(string)
          when :md5
            Digest::MD5.hexdigest(string)
          else
            raise ArgumentError, "Unsupported hash algorithm: #{algorithm}"
          end
        end

        ##
        # Safely parse JSON with error handling
        #
        # @param json_string [String] JSON string to parse
        # @param default [Object] Default value if parsing fails
        # @return [Object] Parsed JSON or default value
        def safe_json_parse(json_string, default: nil)
          JSON.parse(json_string)
        rescue JSON::ParserError
          default
        end

        ##
        # Deep merge two hashes
        #
        # @param hash1 [Hash] First hash
        # @param hash2 [Hash] Second hash
        # @return [Hash] Merged hash
        def deep_merge(hash1, hash2)
          hash1.merge(hash2) do |_key, old_val, new_val|
            if old_val.is_a?(Hash) && new_val.is_a?(Hash)
              deep_merge(old_val, new_val)
            else
              new_val
            end
          end
        end

        ##
        # Convert string to snake_case
        #
        # @param string [String] String to convert
        # @return [String] Snake_case string
        def snake_case(string)
          string
            .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
            .gsub(/([a-z\d])([A-Z])/, '\1_\2')
            .downcase
        end

        ##
        # Convert string to camelCase
        #
        # @param string [String] String to convert
        # @param first_letter_uppercase [Boolean] Whether first letter should be uppercase
        # @return [String] CamelCase string
        def camel_case(string, first_letter_uppercase: false)
          parts = string.split(/[_\-\s]+/)
          result = parts.first.downcase
          result += parts[1..].map(&:capitalize).join if parts.length > 1

          first_letter_uppercase ? result.capitalize : result
        end

        ##
        # Truncate string to specified length
        #
        # @param string [String] String to truncate
        # @param length [Integer] Maximum length
        # @param suffix [String] Suffix to add if truncated
        # @return [String] Truncated string
        def truncate(string, length:, suffix: "...")
          return string if string.length <= length

          truncated_length = length - suffix.length
          return suffix if truncated_length <= 0

          string[0...truncated_length] + suffix
        end

        ##
        # Sanitize string for safe usage
        #
        # @param string [String] String to sanitize
        # @param allowed_chars [Regexp] Allowed characters pattern
        # @return [String] Sanitized string
        def sanitize_string(string, allowed_chars: /[a-zA-Z0-9_\-.]/)
          string.gsub(/[^#{allowed_chars.source}]/, "_")
        end

        ##
        # Check if string is blank (nil, empty, or whitespace only)
        #
        # @param string [String, nil] String to check
        # @return [Boolean] True if blank
        def blank?(string)
          string.nil? || string.strip.empty?
        end

        ##
        # Check if string is present (not blank)
        #
        # @param string [String, nil] String to check
        # @return [Boolean] True if present
        def present?(string)
          !blank?(string)
        end

        ##
        # Retry a block with exponential backoff
        #
        # @param max_attempts [Integer] Maximum number of attempts
        # @param base_delay [Float] Base delay in seconds
        # @param max_delay [Float] Maximum delay in seconds
        # @param backoff_factor [Float] Backoff multiplier
        # @yield Block to retry
        # @return [Object] Block result
        def retry_with_backoff(max_attempts: 3, base_delay: 1.0, max_delay: 60.0, backoff_factor: 2.0)
          attempt = 1

          begin
            yield
          rescue StandardError => e
            raise e unless attempt < max_attempts

            delay = [base_delay * (backoff_factor**(attempt - 1)), max_delay].min
            sleep(delay)
            attempt += 1
            retry
          end
        end

        ##
        # Measure execution time of a block
        #
        # @yield Block to measure
        # @return [Hash] Result with :result and :duration keys
        def measure_execution_time
          start_time = Time.now
          result = yield
          end_time = Time.now

          {
            result: result,
            duration: end_time - start_time
          }
        end

        ##
        # Format bytes in human-readable format
        #
        # @param bytes [Integer] Number of bytes
        # @return [String] Formatted string
        def format_bytes(bytes)
          return "0 B" if bytes.zero?

          units = %w[B KB MB GB TB PB]
          exp = (Math.log(bytes.abs) / Math.log(1024)).floor
          exp = [exp, units.length - 1].min

          "#{(bytes / (1024.0**exp)).round(2)} #{units[exp]}"
        end

        ##
        # Validate email format
        #
        # @param email [String] Email to validate
        # @return [Boolean] True if valid email format
        def valid_email?(email)
          return false if blank?(email)

          # Simple email validation regex
          email.match?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
        end

        ##
        # Validate URL format
        #
        # @param url [String] URL to validate
        # @return [Boolean] True if valid URL format
        def valid_url?(url)
          return false if blank?(url)

          begin
            uri = URI.parse(url)
            uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
          rescue URI::InvalidURIError
            false
          end
        end
      end
    end
  end
end
