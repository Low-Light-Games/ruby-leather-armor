# frozen_string_literal: true

class CreateAdventureSheetClassAbilities < ActiveRecord::Migration[7.1]
  def change
    create_table :adventure_sheet_class_abilities do |t|
      t.bigint :adventure_sheet_id, null: false
      t.string :class_ability_id,   null: false

      t.timestamps
    end

    add_index :adventure_sheet_class_abilities, :adventure_sheet_id,
              name: "index_adv_sheet_class_abilities_on_sheet_id"
    add_index :adventure_sheet_class_abilities,
              %i[adventure_sheet_id class_ability_id],
              unique: true,
              name: "idx_adv_sheet_class_abilities_unique"

    add_foreign_key :adventure_sheet_class_abilities, :adventure_sheets
    add_foreign_key :adventure_sheet_class_abilities, :class_ability_definitions,
                    column: :class_ability_id
  end
end
