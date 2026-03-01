# frozen_string_literal: true

class RemoveLightDungeonMaster < ActiveRecord::Migration[7.1]
  def up
    execute "UPDATE adventures SET dm_mode = 'standard' WHERE dm_mode = 'light'"
    execute "DELETE FROM feature_flags WHERE key = 'light_dungeon_master'"
    execute "UPDATE dm_configs SET settings = (settings::jsonb - 'dm_mode')::json"
  end

  def down
    execute <<-SQL
      INSERT INTO feature_flags (key, enabled, description, created_at, updated_at)
      VALUES ('light_dungeon_master', false, 'Enable the Light Dungeon Master architecture (app-managed combat, locations, NPC attitudes)', NOW(), NOW())
      ON CONFLICT (key) DO NOTHING
    SQL
  end
end
