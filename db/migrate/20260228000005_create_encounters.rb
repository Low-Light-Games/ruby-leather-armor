# frozen_string_literal: true

class CreateEncounters < ActiveRecord::Migration[7.1]
  def change
    create_table :encounters do |t|
      t.references :adventure, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.integer :round_number, default: 0, null: false
      t.integer :current_turn_index, default: 0, null: false
      t.integer :grid_width, null: false, default: 10
      t.integer :grid_height, null: false, default: 10
      t.jsonb :terrain_data, default: {}, null: false
      t.text :narrative_summary

      t.timestamps
    end

    add_index :encounters, [:adventure_id, :status]
  end
end
