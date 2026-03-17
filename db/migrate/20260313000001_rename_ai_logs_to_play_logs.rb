class RenameAiLogsToPlayLogs < ActiveRecord::Migration[7.1]
  def change
    rename_table :ai_logs, :play_logs
    rename_column :play_logs, :call_type, :event_type

    # Rails 7.1 automatically renames associated indexes when renaming a column.
    rename_column :ai_usage_records, :call_type, :event_type
  end
end
