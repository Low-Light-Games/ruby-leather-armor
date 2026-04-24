# frozen_string_literal: true

# Class abilities are resolved live from catalog + sheet class/level; pivots removed.
class DropAdventureSheetClassAbilities < ActiveRecord::Migration[7.1]
  def up
    drop_table :adventure_sheet_class_abilities
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
