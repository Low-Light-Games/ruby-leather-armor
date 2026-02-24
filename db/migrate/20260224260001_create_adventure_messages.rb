class CreateAdventureMessages < ActiveRecord::Migration[7.1]
  def change
    create_table :adventure_messages do |t|
      t.references :adventure, null: false, foreign_key: true
      t.string :role, null: false          # "player", "dm", "system"
      t.text :content, null: false
      t.string :message_type, null: false, default: "narrative"
        # "narrative"          — normal DM narration or player action
        # "sanitization_fail"  — player prompt was rejected
        # "stage_advance"      — story stage was advanced
        # "roll_request"       — DM is requesting a roll
        # "roll_result"        — player submitted a roll result
      t.json :metadata, default: {}        # roll_request details, etc.

      t.timestamps
    end

    add_index :adventure_messages, [:adventure_id, :created_at]
  end
end
