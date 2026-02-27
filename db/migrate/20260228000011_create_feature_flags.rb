# frozen_string_literal: true

class CreateFeatureFlags < ActiveRecord::Migration[7.1]
  def change
    create_table :feature_flags do |t|
      t.string :key, null: false
      t.boolean :enabled, null: false, default: false
      t.string :description

      t.timestamps
    end

    add_index :feature_flags, :key, unique: true

    reversible do |dir|
      dir.up do
        execute <<-SQL
          INSERT INTO feature_flags (key, enabled, description, created_at, updated_at)
          VALUES ('light_dungeon_master', false, 'Enable the Light Dungeon Master architecture (app-managed combat, locations, NPC attitudes)', NOW(), NOW())
        SQL
      end
    end
  end
end
