class CreateAiLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_logs do |t|
      t.references :adventure, null: false, foreign_key: true
      t.string :call_type, null: false        # "sanitization" or "dm_response" or "roll_response"
      t.text :prompt_summary, null: false      # truncated version of what was sent
      t.text :raw_response                     # full AI response text
      t.text :parsed_response                  # the parsed JSON (if successful)
      t.string :status, null: false            # "success", "parse_fallback", "parse_error", "api_error"
      t.text :error_message                    # error details if any

      t.timestamps
    end

    add_index :ai_logs, :created_at
    add_index :ai_logs, :status
  end
end
