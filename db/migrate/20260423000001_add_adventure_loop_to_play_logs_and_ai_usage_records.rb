# frozen_string_literal: true

class AddAdventureLoopToPlayLogsAndAiUsageRecords < ActiveRecord::Migration[7.1]
  def change
    add_column :play_logs, :adventure_loop_id, :bigint
    add_column :play_logs, :loop_sequence_index, :integer
    add_index  :play_logs, :adventure_loop_id, name: "index_play_logs_on_adventure_loop_id"

    add_column :ai_usage_records, :adventure_loop_id, :bigint
    add_column :ai_usage_records, :loop_sequence_index, :integer
    add_index  :ai_usage_records, :adventure_loop_id, name: "index_ai_usage_records_on_adventure_loop_id"
  end
end
