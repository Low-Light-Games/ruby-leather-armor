# frozen_string_literal: true

# Retires the scene_update AI step: drops the two columns it owned
# (`scene_summary`, `scene_history`) on `adventures`. Replaces a per-turn
# AI call whose output was player-visible-only and easily reconstructed
# from the existing AdventureMessage stream when needed (see
# Battlefield::PersistCombatStart#recent_scene_note).
class DropSceneSummaryAndHistoryColumns < ActiveRecord::Migration[7.1]
  def up
    remove_column :adventures, :scene_summary
    remove_column :adventures, :scene_history
  end

  def down
    add_column :adventures, :scene_summary, :text
    add_column :adventures, :scene_history, :jsonb, default: [], null: false
  end
end
