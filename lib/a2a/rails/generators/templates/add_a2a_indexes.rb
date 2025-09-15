# frozen_string_literal: true

class Add<%= table_prefix.classify %>Indexes < ActiveRecord::Migration<%= migration_version %>
  def change
    # Composite indexes for common query patterns
    
    # Tasks table indexes
    add_index :<%= tasks_table_name %>, [:context_id, :status_state], 
              name: "index_<%= tasks_table_name %>_on_context_and_status"
    
    add_index :<%= tasks_table_name %>, [:status_state, :created_at], 
              name: "index_<%= tasks_table_name %>_on_status_and_created"
    
    add_index :<%= tasks_table_name %>, [:type, :status_state], 
              name: "index_<%= tasks_table_name %>_on_type_and_status"
    
    # Index for soft delete queries
    add_index :<%= tasks_table_name %>, [:deleted_at, :status_state], 
              name: "index_<%= tasks_table_name %>_on_deleted_and_status"
    
    <% if postgresql? %>
    # PostgreSQL-specific partial indexes for better performance
    add_index :<%= tasks_table_name %>, :id, 
              where: "deleted_at IS NULL",
              name: "index_<%= tasks_table_name %>_active_tasks"
    
    add_index :<%= tasks_table_name %>, :status_state, 
              where: "deleted_at IS NULL AND status_state IN ('submitted', 'working')",
              name: "index_<%= tasks_table_name %>_active_processing"
    
    # JSON path indexes for common metadata queries
    add_index :<%= tasks_table_name %>, "(metadata->>'priority')", 
              name: "index_<%= tasks_table_name %>_on_priority"
    
    add_index :<%= tasks_table_name %>, "(metadata->>'source')", 
              name: "index_<%= tasks_table_name %>_on_source"
    <% end %>
    
    # Push notification configs indexes
    add_index :<%= push_notification_configs_table_name %>, [:task_id, :active], 
              name: "index_<%= push_notification_configs_table_name %>_on_task_and_active"
    
    add_index :<%= push_notification_configs_table_name %>, [:active, :last_success_at], 
              name: "index_<%= push_notification_configs_table_name %>_on_active_and_success"
    
    # Index for retry logic
    add_index :<%= push_notification_configs_table_name %>, [:retry_count, :last_failure_at], 
              name: "index_<%= push_notification_configs_table_name %>_on_retry"
    
    <% if postgresql? %>
    # PostgreSQL partial index for active configs only
    add_index :<%= push_notification_configs_table_name %>, :task_id, 
              where: "active = true AND deleted_at IS NULL",
              name: "index_<%= push_notification_configs_table_name %>_active_only"
    <% end %>
  end
end