# frozen_string_literal: true

class CreateSheetItems < ActiveRecord::Migration[7.1]
  def change
    create_table :sheet_items do |t|
      t.references :sheet, null: false, foreign_key: true
      t.string     :item_definition_id, null: false
      t.integer    :quantity,            null: false, default: 1
      t.boolean    :equipped,            null: false, default: false
      t.string     :slot_override       # ring_1, ring_2, or nil (use item_definition.slot)

      t.timestamps
    end

    add_foreign_key :sheet_items, :item_definitions, column: :item_definition_id
    add_index :sheet_items, :item_definition_id
  end
end
