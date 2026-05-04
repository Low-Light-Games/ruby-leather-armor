# frozen_string_literal: true

# Drops the five non-combat micro-context JSONB columns. NPC- and
# location-shaped reads now flow through `adventure_npcs`,
# `adventure_locations`, and `adventure_narrative_facts`. `combat_context`
# is preserved — it is the only structured per-adventure state that
# survived the epic.
class DropMicroContextColumns < ActiveRecord::Migration[7.1]
  COLUMNS = %i[traversal_context social_context exploration_context rest_context inventory_context].freeze

  def up
    COLUMNS.each { |col| remove_column :adventures, col }
  end

  def down
    COLUMNS.each { |col| add_column :adventures, col, :jsonb, default: {}, null: false }
  end
end
