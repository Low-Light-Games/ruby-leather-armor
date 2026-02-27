# frozen_string_literal: true

class CreateEncounterParticipants < ActiveRecord::Migration[7.1]
  def change
    create_table :encounter_participants do |t|
      t.references :encounter, null: false, foreign_key: true
      t.references :adventure_sheet, foreign_key: true
      t.references :creature_sheet, foreign_key: true
      t.string :team, null: false, default: "enemy"
      t.integer :initiative, default: 0, null: false
      t.integer :position_x, default: 0, null: false
      t.integer :position_y, default: 0, null: false
      t.integer :current_hp, default: 0, null: false
      t.jsonb :conditions, default: [], null: false
      t.boolean :is_active, default: true, null: false

      t.timestamps
    end

    add_index :encounter_participants, [:encounter_id, :initiative]
  end
end
