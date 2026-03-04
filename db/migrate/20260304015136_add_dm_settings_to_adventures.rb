class AddDmSettingsToAdventures < ActiveRecord::Migration[7.1]
  def change
    add_column :adventures, :dm_settings, :jsonb, default: {}, null: false
  end
end
