class ChangePlayerMessageFkOnAiLogsToNullify < ActiveRecord::Migration[7.1]
  def change
    remove_foreign_key :ai_logs, column: :player_message_id
    add_foreign_key :ai_logs, :adventure_messages, column: :player_message_id, on_delete: :nullify
  end
end
