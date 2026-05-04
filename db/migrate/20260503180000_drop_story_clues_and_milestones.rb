# frozen_string_literal: true

# Removes the deterministic plot-progression scaffolding (clues and
# milestones). Plot state now emerges from `adventure_narrative_facts`
# retrieval; the Chronicler step that consumed these tables was
# retired in commit 6.
class DropStoryCluesAndMilestones < ActiveRecord::Migration[7.1]
  def up
    drop_table :story_clues
    drop_table :story_milestones
  end

  def down
    create_table :story_clues do |t|
      t.bigint  :story_id, null: false
      t.bigint  :adventure_id
      t.string  :source, default: "manual", null: false
      t.string  :title, null: false
      t.text    :description, null: false
      t.string  :discovery_method, default: "exploration", null: false
      t.bigint  :location_id
      t.bigint  :npc_id
      t.integer :prerequisite_clue_ids, default: [], array: true
      t.text    :reveals_secret
      t.string  :difficulty, default: "moderate", null: false
      t.timestamps
    end
    add_index :story_clues, :story_id
    add_index :story_clues, :adventure_id
    add_index :story_clues, :location_id
    add_index :story_clues, :npc_id

    create_table :story_milestones do |t|
      t.bigint  :story_id, null: false
      t.string  :source, default: "manual", null: false
      t.string  :title, null: false
      t.text    :description, null: false
      t.integer :trigger_clue_ids, default: [], array: true
      t.text    :consequence
      t.timestamps
    end
    add_index :story_milestones, :story_id
  end
end
