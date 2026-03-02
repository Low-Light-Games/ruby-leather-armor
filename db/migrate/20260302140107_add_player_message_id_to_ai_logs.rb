class AddPlayerMessageIdToAiLogs < ActiveRecord::Migration[7.1]
  def change
    add_reference :ai_logs, :player_message, foreign_key: { to_table: :adventure_messages }, null: true
  end
end
