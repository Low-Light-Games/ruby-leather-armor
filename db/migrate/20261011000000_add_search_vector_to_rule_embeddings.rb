# frozen_string_literal: true

# Keyword half of hybrid rules retrieval (Rules::Lookup, behind the
# `hybrid_rules_retrieval` flag). Vector search alone misses intents that name
# a rule by its jargon ("touch AC", "CMD", "5-foot step"); a weighted
# full-text vector over the rule text catches those, and Reciprocal Rank
# Fusion merges the two rankings.
#
# A STORED generated column keeps itself in sync with every write path
# (rules:embed's create!/update!, raw SQL, console) with no callback. The
# table holds ~51 rows, so the rewrite and the GIN build are instant and need
# no concurrent index.
class AddSearchVectorToRuleEmbeddings < ActiveRecord::Migration[7.1]
  def change
    add_column :rule_embeddings, :search_vector, :virtual,
               type: :tsvector,
               stored: true,
               as: <<~SQL.squish
                 setweight(to_tsvector('english'::regconfig, coalesce(name, '')), 'A') ||
                 setweight(to_tsvector('english'::regconfig, coalesce(brief, '')), 'B') ||
                 setweight(to_tsvector('english'::regconfig, body), 'C')
               SQL

    add_index :rule_embeddings, :search_vector, using: :gin
  end
end
