class AddTokenUsageBilling < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_usage_records do |t|
      t.bigint :adventure_id
      t.bigint :user_id
      t.string :pipeline_run_id
      t.bigint :ai_log_id
      t.string :model_id, null: false
      t.integer :input_tokens, null: false, default: 0
      t.integer :output_tokens, null: false, default: 0
      t.integer :reasoning_tokens, null: false, default: 0
      t.integer :total_tokens, null: false, default: 0
      t.bigint :input_cost_microdollars, null: false, default: 0
      t.bigint :output_cost_microdollars, null: false, default: 0
      t.bigint :total_cost_microdollars, null: false, default: 0
      t.timestamps
    end

    add_index :ai_usage_records, :model_id
    add_index :ai_usage_records, :created_at
    add_index :ai_usage_records, [:model_id, :created_at]
    add_index :ai_usage_records, :adventure_id
    add_index :ai_usage_records, :user_id
    add_index :ai_usage_records, :pipeline_run_id
    add_index :ai_usage_records, :ai_log_id

    add_column :ai_logs, :ai_usage_record_id, :bigint
    add_index :ai_logs, :ai_usage_record_id
    add_foreign_key :ai_logs, :ai_usage_records, on_delete: :nullify
  end
end
