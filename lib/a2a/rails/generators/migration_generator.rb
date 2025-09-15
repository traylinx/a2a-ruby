# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

##
# Rails generator for creating A2A database migrations
#
# This generator creates database tables needed for A2A task storage,
# push notification configurations, and other persistent data.
#
# @example
#   rails generate a2a:migration
#   rails generate a2a:migration --skip-tasks
#   rails generate a2a:migration --with-indexes
#
class A2A::Rails::Generators::MigrationGenerator < ActiveRecord::Generators::Base
  source_root File.expand_path("templates", __dir__)

  class_option :skip_tasks, type: :boolean, default: false,
    desc: "Skip creating tasks table"

  class_option :skip_push_notifications, type: :boolean, default: false,
    desc: "Skip creating push notification config table"

  class_option :with_indexes, type: :boolean, default: true,
    desc: "Add database indexes for performance"

  class_option :table_prefix, type: :string, default: "a2a_",
    desc: "Prefix for A2A table names"

  desc "Generate A2A database migrations"

  def create_tasks_migration
    return if options[:skip_tasks]

    migration_template "create_a2a_tasks.rb",
      "db/migrate/create_#{table_prefix}tasks.rb",
      migration_version: migration_version

    say "Created tasks migration", :green
  end

  def create_push_notifications_migration
    return if options[:skip_push_notifications]

    migration_template "create_a2a_push_notification_configs.rb",
      "db/migrate/create_#{table_prefix}push_notification_configs.rb",
      migration_version: migration_version

    say "Created push notification configs migration", :green
  end

  def create_indexes_migration
    return unless options[:with_indexes]

    migration_template "add_a2a_indexes.rb",
      "db/migrate/add_#{table_prefix}indexes.rb",
      migration_version: migration_version

    say "Created indexes migration", :green
  end

  def create_models
    template "task_model.rb", "app/models/#{table_prefix}task.rb"
    template "push_notification_config_model.rb",
      "app/models/#{table_prefix}push_notification_config.rb"

    say "Created A2A models", :green
  end

  def show_post_generation_instructions
    say "\n#{"=" * 60}", :green
    say "A2A database migrations generated successfully!", :green
    say "=" * 60, :green

    say "\nNext steps:", :yellow
    say "1. Review the generated migrations in db/migrate/"
    say "2. Run 'rails db:migrate' to create the tables"
    say "3. Customize the models in app/models/ if needed"

    say "\nGenerated tables:", :yellow
    say "  #{table_prefix}tasks - Stores A2A task data"
    say "  #{table_prefix}push_notification_configs - Stores push notification settings"

    if options[:with_indexes]
      say "\nPerformance indexes will be created for:"
      say "  - Task lookups by ID and context_id"
      say "  - Task status filtering"
      say "  - Push notification config lookups"
    end

    say "\nConfiguration:", :yellow
    say "Update config/initializers/a2a.rb to use database storage:"
    say "  config.task_storage = :database"

    say "\nFor more information, visit: https://a2a-protocol.org/sdk/ruby/storage/", :blue
  end

  private

  def migration_version
    if ::Rails.version >= "5.0"
      "[#{::Rails::VERSION::MAJOR}.#{::Rails::VERSION::MINOR}]"
    else
      ""
    end
  end

  def table_prefix
    options[:table_prefix]
  end

  def tasks_table_name
    "#{table_prefix}tasks"
  end

  def push_notification_configs_table_name
    "#{table_prefix}push_notification_configs"
  end

  def with_indexes?
    options[:with_indexes]
  end

  def model_class_name(base_name)
    "#{table_prefix.classify}#{base_name.classify}"
  end

  def model_file_name(base_name)
    "#{table_prefix}#{base_name.underscore}"
  end

  # Helper methods for templates
  def json_column_type
    # Use jsonb for PostgreSQL, json for others
    if postgresql?
      "jsonb"
    else
      "json"
    end
  end

  def text_column_type
    # Use text for larger content
    "text"
  end

  def uuid_column_type
    if postgresql?
      "uuid"
    else
      "string"
    end
  end

  def postgresql?
    # Try to detect PostgreSQL adapter
    return false unless defined?(ActiveRecord::Base)

    begin
      ActiveRecord::Base.connection.adapter_name.downcase.include?("postgresql")
    rescue StandardError
      false
    end
  end

  def mysql?
    return false unless defined?(ActiveRecord::Base)

    begin
      adapter_name = ActiveRecord::Base.connection.adapter_name.downcase
      adapter_name.include?("mysql") || adapter_name.include?("trilogy")
    rescue StandardError
      false
    end
  end

  def sqlite?
    return false unless defined?(ActiveRecord::Base)

    begin
      ActiveRecord::Base.connection.adapter_name.downcase.include?("sqlite")
    rescue StandardError
      false
    end
  end

  # Generate appropriate column definitions based on database adapter
  def id_column_definition
    if postgresql?
      "t.uuid :id, primary_key: true, default: 'gen_random_uuid()'"
    else
      "t.string :id, primary_key: true, limit: 36"
    end
  end

  def uuid_column_definition(name, **options)
    if postgresql?
      "t.uuid :#{name}#{format_column_options(options)}"
    else
      "t.string :#{name}, limit: 36#{format_column_options(options)}"
    end
  end

  def json_column_definition(name, **options)
    "t.#{json_column_type} :#{name}#{format_column_options(options)}"
  end

  def format_column_options(options)
    return "" if options.empty?

    formatted_options = options.map do |key, value|
      case value
      when String
        "#{key}: '#{value}'"
      when Symbol
        "#{key}: :#{value}"
      else
        "#{key}: #{value}"
      end
    end

    ", #{formatted_options.join(", ")}"
  end
end
