# frozen_string_literal: true

class RefactorAdventureSheets < ActiveRecord::Migration[7.1]
  def up
    # 1. Drop old pivot-only adventure_sheets
    drop_table :adventure_sheets

    # 2. Delete any snapshot sheets (orphans from old architecture)
    execute "DELETE FROM sheets WHERE snapshot = true"

    # 3. Remove snapshot column from sheets (keep level)
    remove_index :sheets, :snapshot
    remove_column :sheets, :snapshot

    # 4. Create new adventure_sheets with full character data + dynamic fields
    create_table :adventure_sheets do |t|
      t.references :adventure, null: false, foreign_key: true
      t.references :sheet, foreign_key: true # nullable — original sheet may be deleted later

      # Copied character data
      t.string  :name,                  null: false
      t.text    :description
      t.integer :strength,              null: false
      t.integer :intelligence,          null: false
      t.integer :dexterity,             null: false
      t.integer :constitution,          null: false
      t.integer :wisdom,                null: false
      t.integer :charisma,              null: false
      t.string  :race
      t.string  :racial_bonus_attribute
      t.string  :character_class
      t.string  :subclass
      t.integer :level,                 null: false, default: 1
      t.json    :details

      # Dynamic adventure fields (moved from adventures)
      t.integer :gold,    null: false, default: 0
      t.integer :hp,      null: false, default: 0
      t.integer :max_hp,  null: false, default: 0
      t.text    :items
      t.text    :effects

      t.timestamps
    end

    # 5. Remove dynamic fields from adventures
    remove_column :adventures, :character_gold
    remove_column :adventures, :character_hp
    remove_column :adventures, :character_max_hp
    remove_column :adventures, :character_items
    remove_column :adventures, :character_effects
  end

  def down
    # Re-add dynamic fields to adventures
    add_column :adventures, :character_gold, :integer, default: 0, null: false
    add_column :adventures, :character_hp, :integer, default: 0, null: false
    add_column :adventures, :character_max_hp, :integer, default: 0, null: false
    add_column :adventures, :character_items, :text
    add_column :adventures, :character_effects, :text

    # Drop the new adventure_sheets
    drop_table :adventure_sheets

    # Re-add snapshot to sheets
    add_column :sheets, :snapshot, :boolean, default: false, null: false
    add_index :sheets, :snapshot

    # Re-create old pivot adventure_sheets
    create_table :adventure_sheets do |t|
      t.references :adventure, null: false, foreign_key: true
      t.references :sheet, null: false, foreign_key: true
      t.string :role, null: false
      t.timestamps
    end
    add_index :adventure_sheets, [:adventure_id, :role], unique: true
  end
end
