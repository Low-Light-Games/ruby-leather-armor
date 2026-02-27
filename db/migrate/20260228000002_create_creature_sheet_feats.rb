# frozen_string_literal: true

class CreateCreatureSheetFeats < ActiveRecord::Migration[7.1]
  def change
    create_table :creature_sheet_feats do |t|
      t.references :creature_sheet, null: false, foreign_key: true
      t.string :feat_id, null: false
      t.string :choice

      t.timestamps
    end

    add_foreign_key :creature_sheet_feats, :feat_definitions, column: :feat_id
    add_index :creature_sheet_feats, [:creature_sheet_id, :feat_id, :choice],
              unique: true, name: "idx_creature_sheet_feats_unique"
  end
end
