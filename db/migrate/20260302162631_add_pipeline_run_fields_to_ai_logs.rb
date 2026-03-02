class AddPipelineRunFieldsToAiLogs < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_logs, :pipeline_run_id, :string
    add_column :ai_logs, :player_message_content, :text
    add_index  :ai_logs, :pipeline_run_id
  end
end
