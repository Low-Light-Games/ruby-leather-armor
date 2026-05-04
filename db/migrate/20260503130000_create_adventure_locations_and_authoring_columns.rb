# frozen_string_literal: true

# Schema half of the new authoring + world model:
#
# * `adventure_locations` — per-adventure location store with (x, y)
#   float coordinates plus an embedding for fuzzy-match queries (e.g.
#   SanityChecker resolving "the gatehouse" against canonical names).
#   Two row sources coexist: 'seed' (from authored StoryLocation rows
#   placed deterministically by Vogel-spiral) and 'runtime' (future use
#   for AI-introduced impromptu locations).
#
# * `Story.world_terrain` — single global terrain per Story; combines
#   with `Adventure.coordinate_scale` and DmConfig per-terrain speed
#   factors to produce travel-time math from euclidean coordinate
#   distance.
#
# * `Story.seed_facts` — authored fact list, AI-extracted from premise
#   + opening_message at story save (Commit 7) and bulk-inserted into
#   `adventure_narrative_facts` at adventure creation.
#
# * `Story.opening_message` — author-written prose rendered as the
#   player's first AdventureMessage at adventure creation.
#
# * `Adventure.coordinate_scale` — coordinate-unit-to-mile factor;
#   per-adventure so different stories can scope their geography.
#
# Dark commit (no consumer reads these yet). Existing dying columns
# (Story.initial_summary, Story.initial_contexts, Adventure.*_context)
# stay until later commits drop them alongside their consumers.
class CreateAdventureLocationsAndAuthoringColumns < ActiveRecord::Migration[7.1]
  def change
    create_table :adventure_locations do |t|
      t.references :adventure, null: false, foreign_key: true
      t.references :story_location, null: true, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.float :x, null: false, default: 0.0
      t.float :y, null: false, default: 0.0
      t.string :source, null: false
      t.vector :embedding, limit: 1536
      t.timestamps
    end

    add_index :adventure_locations,
              [:adventure_id, :name],
              unique: true,
              where: "source = 'seed'",
              name: "index_adventure_locations_seed_unique_per_adventure"

    add_index :adventure_locations,
              :embedding,
              using: :hnsw,
              opclass: :vector_cosine_ops,
              name: "index_adventure_locations_on_embedding_hnsw"

    add_column :stories, :world_terrain,   :string, null: false, default: "plains"
    add_column :stories, :seed_facts,      :jsonb,  null: false, default: []
    add_column :stories, :opening_message, :text,   null: false, default: ""

    add_column :adventures, :coordinate_scale, :float, null: false, default: 1.0
  end
end
