class CreateAdventureLoops < ActiveRecord::Migration[7.1]
  def change
    create_table :adventure_loops do |t|
      t.references :adventure, null: false, foreign_key: true
      t.string :pipeline_run_id, null: false
      t.integer :sequence_index, null: false, default: 0
      t.text :raw_action
      t.text :player_intent
      t.string :category
      t.string :status, null: false, default: "pending"
      t.jsonb :tags, null: false, default: {}
      t.jsonb :data, null: false, default: {}
      t.jsonb :timeline, null: false, default: []
      t.timestamps
    end

    add_index :adventure_loops, :pipeline_run_id
    add_index :adventure_loops, [:adventure_id, :created_at]
    add_index :adventure_loops, [:pipeline_run_id, :status]
  end
end
