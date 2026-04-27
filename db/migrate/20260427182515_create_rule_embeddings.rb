# frozen_string_literal: true

# Stores per-rule pgvector embeddings for the rules manifest defined in
# `app/services/dungeon_master/rules/entries/*.yml`. Backs RAG-style
# retrieval that replaces the rules-manifest dump in the new
# RollRequest evaluation step.
#
# Design notes:
#
# * `slug` is the YAML key from the rules entries — the same value the
#   rest of the pipeline already uses with `Rules.fetch(*slugs)`. Unique
#   so re-running the backfill task is idempotent (upserts by slug).
# * `domain` is denormalized off the YAML file the slug came from so we
#   can scope retrieval if a future caller wants per-domain RAG. Today
#   the RollRequest path queries across all domains.
# * `embedding vector(1536)` matches `text-embedding-3-small`, the same
#   model and dimension Loremaster uses (`adventure_narrative_facts`).
#   Reusing the model means one embedding-dimension reality across the
#   app and zero new model-config surface.
# * `text_digest` is a SHA1 of the embedded text. The backfill task uses
#   it to skip rows whose source rule text is unchanged, so re-running
#   the task after `Rules.clear_cache!` does not re-embed the entire
#   corpus.
# * HNSW + `vector_cosine_ops` mirrors the existing
#   `index_narrative_facts_on_embedding_hnsw` index — same retrieval
#   shape, same operator class, same `neighbor` gem usage.
class CreateRuleEmbeddings < ActiveRecord::Migration[7.1]
  def change
    create_table :rule_embeddings do |t|
      t.string :slug, null: false
      t.string :domain, null: false
      t.string :name, null: false
      t.text :brief
      t.text :body, null: false
      t.string :text_digest, null: false
      t.vector :embedding, limit: 1536
      t.timestamps
    end

    add_index :rule_embeddings, :slug, unique: true
    add_index :rule_embeddings, :domain

    add_index :rule_embeddings,
              :embedding,
              using: :hnsw,
              opclass: :vector_cosine_ops,
              name: "index_rule_embeddings_on_embedding_hnsw"
  end
end
