# frozen_string_literal: true

# Creates the per-adventure narrative facts store that backs the
# World Consistency Check. Loremaster is the sole writer (§18
# single-writer invariant); reads happen from `Lore::FactsLookup` via
# pgvector cosine similarity.
#
# Column-by-column rationale lives in the plan
# (narrative_facts_store_for_world_sanity_da8d8488.plan.md, §"Gem / schema").
# Key points the migration encodes:
#
# * `embedding vector(1536)` — matches OpenAI `text-embedding-3-small`.
# * Partial btree on (adventure_id) WHERE invalidated_at_loop_id IS NULL
#   keeps "active facts for this adventure" lookups cheap even when
#   invalidated rows accumulate over a long campaign.
# * Partial unique (adventure_id, introduced_at_loop_id, source_idx)
#   WHERE source = 'loremaster' — idempotency key for at-most-once retry
#   of a Loremaster turn write. Seed rows (source = 'seed',
#   introduced_at_loop_id IS NULL) are intentionally excluded.
# * HNSW index over embedding with vector_cosine_ops — the index
#   `neighbor` expects for cosine-distance nearest-neighbor lookups.
class CreateAdventureNarrativeFacts < ActiveRecord::Migration[7.1]
  def change
    create_table :adventure_narrative_facts do |t|
      t.references :adventure, null: false, foreign_key: true
      t.text :text, null: false
      t.string :kind, null: false
      t.text :entities, array: true, default: []
      t.string :polarity, null: false, default: "asserts"
      t.vector :embedding, limit: 1536
      t.references :introduced_at_loop,
                   foreign_key: { to_table: :adventure_loops },
                   null: true
      t.references :invalidated_at_loop,
                   foreign_key: { to_table: :adventure_loops },
                   null: true
      t.references :invalidated_by_fact,
                   foreign_key: { to_table: :adventure_narrative_facts },
                   null: true
      t.string :source, null: false
      t.integer :source_idx, null: true
      t.datetime :created_at, null: false
    end

    add_index :adventure_narrative_facts,
              :adventure_id,
              where: "invalidated_at_loop_id IS NULL",
              name: "index_narrative_facts_active_by_adventure"

    add_index :adventure_narrative_facts,
              [:adventure_id, :introduced_at_loop_id, :source_idx],
              unique: true,
              where: "source = 'loremaster'",
              name: "index_narrative_facts_loremaster_source_idx_uniq"

    add_index :adventure_narrative_facts,
              :embedding,
              using: :hnsw,
              opclass: :vector_cosine_ops,
              name: "index_narrative_facts_on_embedding_hnsw"
  end
end
