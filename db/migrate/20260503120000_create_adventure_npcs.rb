# frozen_string_literal: true

# Per-adventure NPC store. Replaces `traversal_context["nearby_npcs"]`
# and the Combat::SocialEventTrigger reads off `social_context` (those
# repoints land in a later commit; this migration is dark — no consumer
# yet).
#
# Two row sources coexist (Decision 17, micro-context removal epic):
# * `source = 'seed'`  — derived from authored `StoryNpc` rows at
#                         adventure creation. Stable per (adventure, name).
# * `source = 'runtime'` — AI-introduced mid-adventure (future use).
#
# Index notes:
# * Partial unique on (adventure_id, name) WHERE source = 'seed' makes
#   re-seeding idempotent if SeedFromAdventure runs twice.
# * Plain index on (adventure_id, location_name) for the hot path
#   "who's at this location?" used by EncounterWarmasterBridge and
#   SocialEventTrigger after the repoint.
# * HNSW over `embedding` for fuzzy-match queries (e.g. SanityChecker
#   resolving "the captain" against canonical NPC names).
class CreateAdventureNpcs < ActiveRecord::Migration[7.1]
  def change
    create_table :adventure_npcs do |t|
      t.references :adventure, null: false, foreign_key: true
      t.references :story_npc, null: true, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :attitude, null: false, default: "indifferent"
      t.string :location_name
      t.string :source, null: false
      t.vector :embedding, limit: 1536
      t.references :last_seen_loop,
                   foreign_key: { to_table: :adventure_loops },
                   null: true
      t.timestamps
    end

    add_index :adventure_npcs,
              [:adventure_id, :name],
              unique: true,
              where: "source = 'seed'",
              name: "index_adventure_npcs_seed_unique_per_adventure"

    add_index :adventure_npcs,
              [:adventure_id, :location_name],
              name: "index_adventure_npcs_on_adventure_and_location"

    add_index :adventure_npcs,
              :embedding,
              using: :hnsw,
              opclass: :vector_cosine_ops,
              name: "index_adventure_npcs_on_embedding_hnsw"
  end
end
