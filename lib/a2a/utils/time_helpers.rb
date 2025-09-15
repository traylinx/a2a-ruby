# frozen_string_literal: true

##
# Time handling utilities for consistent timestamp generation
#
# Provides compatibility layer for Time.current vs Time.now and
# consistent timestamp formatting across different Ruby versions and environments.
#
module A2A
  module Utils
    module TimeHelpers
      class << self
        ##
        # Get current time with Rails compatibility
        #
        # Uses Time.current if available (Rails), otherwise falls back to Time.now
        #
        # @return [Time] Current time
        def current_time
          if defined?(Time.current)
            Time.current
          else
            Time.now
          end
        end

        ##
        # Get current timestamp in ISO8601 format
        #
        # @return [String] ISO8601 formatted timestamp
        def current_timestamp
          current_time.utc.iso8601
        end

        ##
        # Get current timestamp for tests (always uses Time.now for consistency)
        #
        # @return [String] ISO8601 formatted timestamp
        def test_timestamp
          Time.now.utc.iso8601
        end

        ##
        # Get current time as integer (Unix timestamp)
        #
        # @return [Integer] Unix timestamp
        def current_time_i
          current_time.to_i
        end

        ##
        # Parse ISO8601 timestamp string
        #
        # @param timestamp [String] ISO8601 timestamp string
        # @return [Time] Parsed time object
        def parse_timestamp(timestamp)
          Time.parse(timestamp)
        rescue ArgumentError => e
          raise A2A::Errors::InvalidTimestamp, "Invalid timestamp format: #{timestamp} - #{e.message}"
        end

        ##
        # Format time as ISO8601 string
        #
        # @param time [Time] Time object to format
        # @return [String] ISO8601 formatted string
        def format_timestamp(time)
          time.utc.iso8601
        end

        ##
        # Add time duration to current time
        #
        # @param duration [Numeric] Duration in seconds
        # @return [Time] Future time
        def time_from_now(duration)
          current_time + duration
        end

        ##
        # Add time duration to current time and format as ISO8601
        #
        # @param duration [Numeric] Duration in seconds
        # @return [String] ISO8601 formatted future timestamp
        def timestamp_from_now(duration)
          format_timestamp(time_from_now(duration))
        end

        ##
        # Check if timestamp is in the past
        #
        # @param timestamp [String, Time] Timestamp to check
        # @return [Boolean] True if timestamp is in the past
        def past?(timestamp)
          time = timestamp.is_a?(String) ? parse_timestamp(timestamp) : timestamp
          time < current_time
        end

        ##
        # Check if timestamp is in the future
        #
        # @param timestamp [String, Time] Timestamp to check
        # @return [Boolean] True if timestamp is in the future
        def future?(timestamp)
          time = timestamp.is_a?(String) ? parse_timestamp(timestamp) : timestamp
          time > current_time
        end

        ##
        # Calculate duration between two timestamps
        #
        # @param start_time [String, Time] Start timestamp
        # @param end_time [String, Time] End timestamp (defaults to current time)
        # @return [Float] Duration in seconds
        def duration_between(start_time, end_time = nil)
          start_t = start_time.is_a?(String) ? parse_timestamp(start_time) : start_time
          end_t = if end_time
                    end_time.is_a?(String) ? parse_timestamp(end_time) : end_time
                  else
                    current_time
                  end

          end_t - start_t
        end

        ##
        # Format duration in human-readable format
        #
        # @param duration [Numeric] Duration in seconds
        # @return [String] Human-readable duration
        def format_duration(duration)
          return "0s" if duration.zero?

          parts = []

          if duration >= 86_400 # days
            days = (duration / 86_400).floor
            parts << "#{days}d"
            duration %= 86_400
          end

          if duration >= 3600 # hours
            hours = (duration / 3600).floor
            parts << "#{hours}h"
            duration %= 3600
          end

          if duration >= 60 # minutes
            minutes = (duration / 60).floor
            parts << "#{minutes}m"
            duration %= 60
          end

          if duration.positive? || parts.empty?
            parts << if duration == duration.to_i
                       "#{duration.to_i}s"
                     else
                       "#{duration.round(2)}s"
                     end
          end

          parts.join(" ")
        end
      end
    end
  end
end
