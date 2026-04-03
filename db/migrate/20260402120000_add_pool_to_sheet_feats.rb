# frozen_string_literal: true

class AddPoolToSheetFeats < ActiveRecord::Migration[7.1]
  def change
    add_column :sheet_feats, :pool, :string, null: false, default: "general"
    add_column :adventure_sheet_feats, :pool, :string, null: false, default: "general"
  end
end
