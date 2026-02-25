# frozen_string_literal: true

class CreateSpellDefinitions < ActiveRecord::Migration[7.1]
  def change
    create_table :spell_definitions, id: false do |t|
      t.string :id, primary_key: true, null: false # e.g. "magic_missile"
      t.string :name, null: false
      t.string :school, null: false # abjuration, conjuration, etc.
      t.string :subschool
      t.jsonb  :descriptors, default: [], null: false
      t.jsonb  :class_levels, default: {}, null: false # { "wizard": 1, "cleric": 0 }
      t.jsonb  :components, default: [], null: false   # ["V", "S", "M"]
      t.string :material_component
      t.string :casting_time
      t.string :range
      t.string :duration
      t.string :saving_throw
      t.boolean :spell_resistance, default: false, null: false
      t.jsonb  :effects, default: [], null: false
      t.text   :summary
      t.timestamps
    end

    add_index :spell_definitions, :school
    add_index :spell_definitions, :name
    add_index :spell_definitions, :class_levels, using: :gin
  end
end
