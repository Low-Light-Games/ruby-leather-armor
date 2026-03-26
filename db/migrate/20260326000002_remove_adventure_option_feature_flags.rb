# frozen_string_literal: true

class RemoveAdventureOptionFeatureFlags < ActiveRecord::Migration[7.1]
  KEYS = %w[directed_dm skip_world_sanity_check].freeze

  def up
    execute <<-SQL
      DELETE FROM feature_flags WHERE key IN (#{KEYS.map { |k| "'#{k}'" }.join(", ")})
    SQL
  end

  def down
    execute <<-SQL
      INSERT INTO feature_flags (key, enabled, description, created_at, updated_at) VALUES
        ('directed_dm', false, 'Allow players to opt into a directed play style where the DM actively gives direction and choices', NOW(), NOW()),
        ('skip_world_sanity_check', false, 'Allow players to opt out of the world consistency check, letting any action through regardless of scene state', NOW(), NOW())
      ON CONFLICT (key) DO NOTHING
    SQL
  end
end
