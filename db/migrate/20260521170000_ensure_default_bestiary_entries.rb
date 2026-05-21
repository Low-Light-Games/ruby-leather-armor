# frozen_string_literal: true

class EnsureDefaultBestiaryEntries < ActiveRecord::Migration[7.1]
  def up
    load Rails.root.join("db/seeds/default_bestiary.rb")
  end

  def down
    execute <<~SQL.squish
      DELETE FROM bestiary_entries
      WHERE id IN ('default_beast', 'default_fighter', 'default_goblinoid', 'default_spellcaster', 'default_commoner')
    SQL
  end
end
