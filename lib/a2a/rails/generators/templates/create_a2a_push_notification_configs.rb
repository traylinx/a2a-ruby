# frozen_string_literal: true

class Create<%= table_prefix.classify %>PushNotificationConfigs < ActiveRecord::Migration<%= migration_version %>
  def change
    create_table :<%= push_notification_configs_table_name %>, id: false do |t|
      # Primary key
      <% if postgresql? %>
      t.uuid :id, primary_key: true, default: "gen_random_uuid()"
      t.uuid :task_id, null: false
      <% else %>
      t.string :id, primary_key: true, limit: 36, null: false
      t.string :task_id, limit: 36, null: false
      <% end %>
      
      # Push notification configuration
      t.string :url, null: false
      t.string :token, null: true
      t.<%= json_column_type %> :authentication, null: true, default: -> { 
        <% if postgresql? %>
        "'{}'::jsonb"
        <% else %>
        "'{}'"
        <% end %>
      }
      
      # Configuration metadata
      t.<%= json_column_type %> :metadata, null: true, default: -> { 
        <% if postgresql? %>
        "'{}'::jsonb"
        <% else %>
        "'{}'"
        <% end %>
      }
      
      # Status tracking
      t.boolean :active, null: false, default: true
      t.integer :retry_count, null: false, default: 0
      t.datetime :last_success_at, null: true
      t.datetime :last_failure_at, null: true
      t.text :last_error, null: true
      
      # Timestamps
      t.timestamps null: false
      
      # Soft delete support
      t.datetime :deleted_at, null: true
    end

    <% if with_indexes? %>
    # Add indexes for performance
    add_index :<%= push_notification_configs_table_name %>, :id, unique: true
    add_index :<%= push_notification_configs_table_name %>, :task_id
    add_index :<%= push_notification_configs_table_name %>, :active
    add_index :<%= push_notification_configs_table_name %>, :created_at
    add_index :<%= push_notification_configs_table_name %>, :deleted_at
    
    <% if postgresql? %>
    # PostgreSQL-specific indexes for JSON columns
    add_index :<%= push_notification_configs_table_name %>, :authentication, using: :gin
    add_index :<%= push_notification_configs_table_name %>, :metadata, using: :gin
    <% end %>
    <% end %>

    # Foreign key constraint to tasks table
    add_foreign_key :<%= push_notification_configs_table_name %>, :<%= tasks_table_name %>, 
                    column: :task_id, primary_key: :id, on_delete: :cascade
  end
end