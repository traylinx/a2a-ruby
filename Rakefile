# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

# Test tasks
RSpec::Core::RakeTask.new(:spec) do |task|
  task.rspec_opts = "--format documentation --color"
end

# Specific test suites
namespace :spec do
  RSpec::Core::RakeTask.new(:unit) do |task|
    task.pattern = "spec/a2a/**/*_spec.rb"
    task.rspec_opts = "--format documentation --color"
  end

  RSpec::Core::RakeTask.new(:integration) do |task|
    task.pattern = "spec/integration/**/*_spec.rb"
    task.rspec_opts = "--format documentation --color"
  end

  RSpec::Core::RakeTask.new(:compliance) do |task|
    task.pattern = "spec/compliance/**/*_spec.rb"
    task.rspec_opts = "--format documentation --color"
  end

  RSpec::Core::RakeTask.new(:performance) do |task|
    task.pattern = "spec/performance/**/*_spec.rb"
    task.rspec_opts = "--format documentation --color"
  end

  desc "Run all tests with coverage"
  RSpec::Core::RakeTask.new(:coverage) do |task|
    task.rspec_opts = "--format documentation --color"
  end
end

# Load optional tasks if gems are available
begin
  require "rubocop/rake_task"
  RuboCop::RakeTask.new(:rubocop) do |task|
    task.options = ["--display-cop-names"]
  end

  desc "Auto-correct RuboCop offenses"
  RuboCop::RakeTask.new("rubocop:autocorrect") do |task|
    task.options = ["--autocorrect"]
  end
rescue LoadError
  # RuboCop not available
end

begin
  require "yard"
  YARD::Rake::YardocTask.new(:yard) do |task|
    task.files = ["lib/**/*.rb"]
    task.options = ["--markup", "markdown"]
  end
rescue LoadError
  # YARD not available
end

# CI task that runs all tests
desc "Run all tests for CI"
task ci: %w[rubocop spec:unit spec:integration spec:compliance]

# Changelog management
namespace :changelog do
  desc "Update changelog with current date for unreleased version"
  task :update_date do
    changelog_path = "CHANGELOG.md"
    current_date = Time.now.strftime("%Y-%m-%d")
    
    unless File.exist?(changelog_path)
      puts "CHANGELOG.md not found!"
      exit 1
    end
    
    content = File.read(changelog_path)
    
    # Replace any unreleased or incorrect dates with current date
    # Pattern matches: ## [version] - YYYY-MM-DD or ## [version] - Unreleased
    updated_content = content.gsub(/^(## \[[^\]]+\]) - (?:\d{4}-\d{2}-\d{2}|Unreleased)$/) do |match|
      version_part = match.split(' - ').first
      "#{version_part} - #{current_date}"
    end
    
    if content != updated_content
      File.write(changelog_path, updated_content)
      puts "Updated CHANGELOG.md with current date: #{current_date}"
    else
      puts "No changelog dates needed updating"
    end
  end
  
  desc "Add new version entry to changelog"
  task :new_version, [:version] do |task, args|
    version = args[:version] || ENV['VERSION']
    
    unless version
      puts "Please provide a version: rake changelog:new_version[1.0.1] or VERSION=1.0.1 rake changelog:new_version"
      exit 1
    end
    
    changelog_path = "CHANGELOG.md"
    current_date = Time.now.strftime("%Y-%m-%d")
    
    unless File.exist?(changelog_path)
      puts "CHANGELOG.md not found!"
      exit 1
    end
    
    content = File.read(changelog_path)
    
    # Find the first ## heading and insert new version before it
    new_entry = <<~ENTRY
      ## [#{version}] - #{current_date}

      ### Added
      - 

      ### Changed
      - 

      ### Fixed
      - 

      ENTRY
    
    # Insert after the header but before the first version entry
    updated_content = content.sub(/^(# Changelog.*?\n\n)/m, "\\1#{new_entry}")
    
    File.write(changelog_path, updated_content)
    puts "Added new version #{version} to CHANGELOG.md with date #{current_date}"
  end
end

# Release tasks
namespace :release do
  desc "Prepare release with updated changelog date"
  task :prepare, [:version] do |task, args|
    version = args[:version] || ENV['VERSION']
    
    if version
      Rake::Task["changelog:new_version"].invoke(version)
    else
      Rake::Task["changelog:update_date"].invoke
    end
    
    puts "Release preparation complete!"
    puts "Don't forget to:"
    puts "1. Update version in lib/a2a/version.rb"
    puts "2. Commit changes"
    puts "3. Create and push git tag: git tag v#{version || 'X.X.X'} && git push origin v#{version || 'X.X.X'}"
  end
end

# Default task
task default: :spec

# Aliases
task test: :spec
task lint: :rubocop if defined?(RuboCop)
task docs: :yard if defined?(YARD)
