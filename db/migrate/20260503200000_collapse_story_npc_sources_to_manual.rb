# frozen_string_literal: true

# Collapses any historical `enricher` / `embellisher` rows on
# `story_npcs.source` to `manual`. Both AI sources were retired earlier
# in the epic and are no longer accepted by the model validation.
class CollapseStoryNpcSourcesToManual < ActiveRecord::Migration[7.1]
  def up
    StoryNpc.where(source: %w[enricher embellisher]).update_all(source: "manual")
  end

  def down
    # No-op: we cannot reconstruct which retired step originally created
    # a given NPC, and the model no longer accepts those values.
  end
end
