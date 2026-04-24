# frozen_string_literal: true

class DropAdventureSheetClassAbilities < ActiveRecord::Migration[7.1]
  def up
    drop_table :adventure_sheet_class_abilities
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
