# frozen_string_literal: true

class AddHiddenFromPlayersToStories < ActiveRecord::Migration[7.1]
  def change
    add_column :stories, :hidden_from_players, :boolean, default: false, null: false
  end
end
