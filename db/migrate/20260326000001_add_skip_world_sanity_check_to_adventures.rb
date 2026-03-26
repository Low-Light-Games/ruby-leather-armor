# frozen_string_literal: true

class AddSkipWorldSanityCheckToAdventures < ActiveRecord::Migration[7.1]
  def change
    add_column :adventures, :skip_world_sanity_check, :boolean, null: false, default: false
  end
end
