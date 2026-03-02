class NullifyAdventureIdOnLogsForRetention < ActiveRecord::Migration[7.1]
  def change
    change_column_null :ai_logs, :adventure_id, true
    remove_foreign_key :ai_logs, :adventures
    add_foreign_key :ai_logs, :adventures, on_delete: :nullify

    change_column_null :dm_logs, :adventure_id, true
    remove_foreign_key :dm_logs, :adventures
    add_foreign_key :dm_logs, :adventures, on_delete: :nullify
  end
end
