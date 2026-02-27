# frozen_string_literal: true

class AddDmModeToAdventures < ActiveRecord::Migration[7.1]
  def change
    add_column :adventures, :dm_mode, :string, default: "standard", null: false
  end
end
