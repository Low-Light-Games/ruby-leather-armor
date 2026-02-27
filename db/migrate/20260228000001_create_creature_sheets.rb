# frozen_string_literal: true

class CreateCreatureSheets < ActiveRecord::Migration[7.1]
  def change
    create_table :creature_sheets do |t|
      t.references :adventure, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :creature_type, null: false, default: "npc"
      t.string :attitude, default: "indifferent"

      t.integer :strength, null: false, default: 10
      t.integer :dexterity, null: false, default: 10
      t.integer :constitution, null: false, default: 10
      t.integer :intelligence, null: false, default: 10
      t.integer :wisdom, null: false, default: 10
      t.integer :charisma, null: false, default: 10

      t.integer :level, default: 1, null: false
      t.string :race
      t.string :racial_bonus_attribute
      t.string :character_class

      t.integer :hp, default: 0, null: false
      t.integer :max_hp, default: 0, null: false

      t.jsonb :derived_stats, default: {}, null: false
      t.string :equipped_armor_id
      t.string :equipped_shield_id
      t.jsonb :equipped_weapons, default: [], null: false
      t.jsonb :details, default: {}, null: false
      t.jsonb :currency, default: { "gold" => 0, "copper" => 0, "silver" => 0, "platinum" => 0 }, null: false

      t.timestamps
    end

    add_index :creature_sheets, [:adventure_id, :name]
  end
end
