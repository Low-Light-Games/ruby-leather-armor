# frozen_string_literal: true

class NullifyLocationFkOnNpcsAndClues < ActiveRecord::Migration[7.1]
  def change
    remove_foreign_key :story_npcs, column: :location_id
    add_foreign_key :story_npcs, :story_locations, column: :location_id, on_delete: :nullify

    remove_foreign_key :story_clues, column: :location_id
    add_foreign_key :story_clues, :story_locations, column: :location_id, on_delete: :nullify
  end
end
