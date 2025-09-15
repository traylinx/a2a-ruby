# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

# Test tasks
RSpec::Core::RakeTask.new(:spec) do |task|
  task.rspec_opts = "--format documentation --color"
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

# Default task
task default: :spec

# Aliases
task test: :spec
task lint: :rubocop if defined?(RuboCop)
task docs: :yard if defined?(YARD)
