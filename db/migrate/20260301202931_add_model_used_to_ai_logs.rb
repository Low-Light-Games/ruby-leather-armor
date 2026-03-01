class AddModelUsedToAiLogs < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_logs, :model_used, :string
  end
end
