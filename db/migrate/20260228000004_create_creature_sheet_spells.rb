# frozen_string_literal: true

class CreateCreatureSheetSpells < ActiveRecord::Migration[7.1]
  def change
    create_table :creature_sheet_spells do |t|
      t.references :creature_sheet, null: false, foreign_key: true
      t.string :spell_id, null: false
      t.string :storage_type, default: "known", null: false

      t.timestamps
    end

    add_foreign_key :creature_sheet_spells, :spell_definitions, column: :spell_id
    add_index :creature_sheet_spells, [:creature_sheet_id, :spell_id, :storage_type],
              unique: true, name: "idx_creature_sheet_spells_unique"
  end
end
