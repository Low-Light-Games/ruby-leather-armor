# frozen_string_literal: true

class AddSkipWorldSanityCheckToAdventures < ActiveRecord::Migration[7.1]
  def change
    add_column :adventures, :skip_world_sanity_check, :boolean, null: false, default: false

    reversible do |dir|
      dir.up do
        execute <<-SQL
          INSERT INTO feature_flags (key, enabled, description, created_at, updated_at)
          VALUES ('skip_world_sanity_check', false, 'Allow players to opt out of the world consistency check, letting any action through regardless of scene state', NOW(), NOW())
          ON CONFLICT (key) DO NOTHING
        SQL
      end
    end
  end
end
