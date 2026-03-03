# frozen_string_literal: true

class AddEnrichmentAndPlotStateToAdventures < ActiveRecord::Migration[7.1]
  def change
    add_column :adventures, :enriched_world, :jsonb, default: {}, null: false
    add_column :adventures, :enriched_premise, :text
    add_column :adventures, :plot_state, :jsonb, default: {}, null: false
  end
end
