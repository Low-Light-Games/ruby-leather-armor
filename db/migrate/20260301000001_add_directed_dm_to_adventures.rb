# frozen_string_literal: true

class AddDirectedDmToAdventures < ActiveRecord::Migration[7.1]
  def change
    add_column :adventures, :directed_dm, :boolean, null: false, default: false

    reversible do |dir|
      dir.up do
        execute <<-SQL
          INSERT INTO feature_flags (key, enabled, description, created_at, updated_at)
          VALUES ('directed_dm', false, 'Allow players to opt into a directed play style where the DM actively gives direction and choices', NOW(), NOW())
          ON CONFLICT (key) DO NOTHING
        SQL
      end
    end
  end
end
