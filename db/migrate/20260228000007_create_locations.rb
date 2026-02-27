# frozen_string_literal: true

class CreateLocations < ActiveRecord::Migration[7.1]
  def change
    create_table :locations do |t|
      t.references :adventure, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :terrain_type, default: "road"
      t.boolean :is_current, default: false, null: false

      t.timestamps
    end

    add_index :locations, [:adventure_id, :name], unique: true
    add_index :locations, [:adventure_id, :is_current]
  end
end
