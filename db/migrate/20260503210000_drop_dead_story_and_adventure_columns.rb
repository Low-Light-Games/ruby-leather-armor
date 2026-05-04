# frozen_string_literal: true

# Drops the columns the epic left as "dying surfaces" once their writers
# (Enricher / Embellisher / Chronicler) were retired. None have live
# readers — confirmed by repo-wide grep before writing this migration.
#
# Story:
# - initial_summary  — written by Embellisher; never read post-epic.
# - initial_contexts — written by Bootstrap to seed the six micro-contexts;
#                      no consumer after micro-contexts were dropped.
#
# Adventure:
# - enriched_world   — written by Embellisher.
# - enriched_premise — written by Embellisher.
# - plot_state       — written by Chronicler.
class DropDeadStoryAndAdventureColumns < ActiveRecord::Migration[7.1]
  def up
    remove_column :stories, :initial_summary
    remove_column :stories, :initial_contexts
    remove_column :adventures, :enriched_world
    remove_column :adventures, :enriched_premise
    remove_column :adventures, :plot_state
  end

  def down
    add_column :stories, :initial_summary, :text
    add_column :stories, :initial_contexts, :jsonb, default: {}, null: false
    add_column :adventures, :enriched_world, :jsonb, default: {}, null: false
    add_column :adventures, :enriched_premise, :text
    add_column :adventures, :plot_state, :jsonb, default: {}, null: false
  end
end
