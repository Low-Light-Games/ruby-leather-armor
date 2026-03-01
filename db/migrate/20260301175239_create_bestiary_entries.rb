# frozen_string_literal: true

class CreateBestiaryEntries < ActiveRecord::Migration[7.1]
  def change
    create_table :bestiary_entries, id: :string do |t|
      t.string :name, null: false
      t.string :source, null: false, default: "Pathfinder Roleplaying Game Reference Document (OGL)"
      t.decimal :cr, precision: 5, scale: 1
      t.string :creature_type
      t.string :alignment
      t.string :size, default: "Medium"
      t.integer :strength, default: 10
      t.integer :dexterity, default: 10
      t.integer :constitution, default: 10
      t.integer :intelligence, default: 10
      t.integer :wisdom, default: 10
      t.integer :charisma, default: 10
      t.string :hp_formula
      t.integer :ac, default: 10
      t.integer :base_attack, default: 0
      t.integer :speed, default: 30
      t.jsonb :special_abilities, default: []
      t.jsonb :feats, default: []
      t.jsonb :skills, default: {}
      t.text :description
      t.string :environment

      t.timestamps
    end

    add_index :bestiary_entries, :cr
    add_index :bestiary_entries, :creature_type
  end
end
