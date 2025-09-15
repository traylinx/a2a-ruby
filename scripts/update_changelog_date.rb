#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to automatically update changelog dates with current system time
# Usage: ruby scripts/update_changelog_date.rb [version]

require 'time'

def update_changelog_date(version = nil)
  changelog_path = 'CHANGELOG.md'
  current_date = Time.now.strftime('%Y-%m-%d')
  
  unless File.exist?(changelog_path)
    puts "ERROR: CHANGELOG.md not found!"
    exit 1
  end
  
  content = File.read(changelog_path)
  original_content = content.dup
  
  if version
    # Update specific version
    pattern = /^(## \[#{Regexp.escape(version)}\]) - (?:\d{4}-\d{2}-\d{2}|Unreleased)$/
    content.gsub!(pattern, "\\1 - #{current_date}")
    puts "Updated version #{version} to date #{current_date}"
  else
    # Update all versions with incorrect or unreleased dates
    content.gsub!(/^(## \[[^\]]+\]) - (?:\d{4}-\d{2}-\d{2}|Unreleased)$/) do |match|
      version_part = match.split(' - ').first
      "#{version_part} - #{current_date}"
    end
    puts "Updated all changelog entries to current date: #{current_date}"
  end
  
  if content != original_content
    File.write(changelog_path, content)
    puts "CHANGELOG.md updated successfully"
  else
    puts "No changes needed in CHANGELOG.md"
  end
end

# Main execution
if __FILE__ == $0
  version = ARGV[0]
  update_changelog_date(version)
end