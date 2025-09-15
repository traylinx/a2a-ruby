# frozen_string_literal: true

class Create<%= table_prefix.classify %>Tasks < ActiveRecord::Migration<%= migration_version %>
  def change
    create_table :<%= tasks_table_name %>, id: false do |t|
      # Primary key - use UUID if PostgreSQL, string otherwise
      <% if postgresql? %>
      t.uuid :id, primary_key: true, default: "gen_random_uuid()"
      t.uuid :context_id, null: false
      <% else %>
      t.string :id, primary_key: true, limit: 36, null: false
      t.string :context_id, limit: 36, null: false
      <% end %>
      
      # Task metadata
      t.string :kind, null: false, default: "task"
      t.string :type, null: true # For task type classification
      
      # Task status information
      t.string :status_state, null: false, default: "submitted"
      t.text :status_message, null: true
      t.decimal :status_progress, precision: 5, scale: 2, null: true
      t.<%= json_column_type %> :status_result, null: true
      t.<%= json_column_type %> :status_error, null: true
      t.datetime :status_updated_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      
      # Task data
      t.<%= json_column_type %> :artifacts, null: true, default: -> { 
        <% if postgresql? %>
        "'[]'::jsonb"
        <% else %>
        "'[]'"
        <% end %>
      }
      t.<%= json_column_type %> :history, null: true, default: -> { 
        <% if postgresql? %>
        "'[]'::jsonb"
        <% else %>
        "'[]'"
        <% end %>
      }
      t.<%= json_column_type %> :metadata, null: true, default: -> { 
        <% if postgresql? %>
        "'{}'::jsonb"
        <% else %>
        "'{}'"
        <% end %>
      }
      
      # Task parameters and configuration
      t.<%= json_column_type %> :params, null: true, default: -> { 
        <% if postgresql? %>
        "'{}'::jsonb"
        <% else %>
        "'{}'"
        <% end %>
      }
      
      # Timestamps
      t.timestamps null: false
      
      # Soft delete support
      t.datetime :deleted_at, null: true
    end

    <% if with_indexes? %>
    # Add indexes for performance
    add_index :<%= tasks_table_name %>, :id, unique: true
    add_index :<%= tasks_table_name %>, :context_id
    add_index :<%= tasks_table_name %>, :status_state
    add_index :<%= tasks_table_name %>, :type
    add_index :<%= tasks_table_name %>, :created_at
    add_index :<%= tasks_table_name %>, :status_updated_at
    add_index :<%= tasks_table_name %>, :deleted_at
    
    <% if postgresql? %>
    # PostgreSQL-specific indexes for JSON columns
    add_index :<%= tasks_table_name %>, :metadata, using: :gin
    add_index :<%= tasks_table_name %>, :params, using: :gin
    <% end %>
    <% end %>
  end
end