class AddPipelineProfiling < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_logs, :duration_ms, :integer

    create_table :pipeline_runs do |t|
      t.string :pipeline_run_id, null: false
      t.bigint :adventure_id, null: false
      t.bigint :player_message_id
      t.string :status, null: false, default: "running"
      t.integer :active_duration_ms, null: false, default: 0
      t.integer :step_count, null: false, default: 0
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.timestamps
    end

    add_index :pipeline_runs, :pipeline_run_id, unique: true
    add_index :pipeline_runs, :adventure_id
    add_index :pipeline_runs, :started_at
  end
end
