# frozen_string_literal: true

class CreateCreatureSheetItems < ActiveRecord::Migration[7.1]
  def change
    create_table :creature_sheet_items do |t|
      t.references :creature_sheet, null: false, foreign_key: true
      t.string :item_definition_id, null: false
      t.integer :quantity, default: 1, null: false
      t.boolean :equipped, default: false, null: false
      t.string :slot_override

      t.timestamps
    end

    add_foreign_key :creature_sheet_items, :item_definitions
    add_index :creature_sheet_items, :item_definition_id
  end
end
