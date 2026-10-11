# frozen_string_literal: true

# ~51 rows, so the table rewrite and GIN build need no concurrent index.
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
