# frozen_string_literal: true

class CreateAdventureSheets < ActiveRecord::Migration[7.1]
  def change
    create_table :adventure_sheets do |t|
      t.references :adventure, null: false, foreign_key: true
      t.references :sheet, null: false, foreign_key: true
      t.string :role, null: false # 'original' or 'snapshot'
      t.timestamps
    end

    add_index :adventure_sheets, [:adventure_id, :role], unique: true
  end
end
