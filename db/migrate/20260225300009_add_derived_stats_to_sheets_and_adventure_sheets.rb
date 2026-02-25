# frozen_string_literal: true

class AddDerivedStatsToSheetsAndAdventureSheets < ActiveRecord::Migration[7.1]
  def change
    add_column :sheets, :derived_stats, :jsonb, default: {}, null: false
    add_column :adventure_sheets, :derived_stats, :jsonb, default: {}, null: false
  end
end
