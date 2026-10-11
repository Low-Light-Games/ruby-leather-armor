# frozen_string_literal: true

class RuleEmbedding < ApplicationRecord
  has_neighbors :embedding, dimensions: 1536

  validates :slug,        presence: true, uniqueness: true
  validates :domain,      presence: true
  validates :name,        presence: true
  validates :body,        presence: true
  validates :text_digest, presence: true

  scope :for_domain, ->(domain) { where(domain: domain) }
  scope :nearest_to, lambda { |embedding, limit:|
    nearest_neighbors(:embedding, embedding, distance: 'cosine').limit(limit)
  }

  # Full-text ranking over the generated `search_vector` column. Player intents
  # are free prose, so the query ORs its lexemes ("I try to grapple the bandit"
  # must not require every word to appear); ts_rank then favours rules that
  # match more terms, and terms in the rule name (weight A).
  scope :keyword_ranked, lambda { |text, limit:|
    query = sanitize_sql_array(
      ["replace(plainto_tsquery('english', ?)::text, ' & ', ' | ')::tsquery", text.to_s]
    )

    select(arel_table[Arel.star], Arel.sql("ts_rank(search_vector, #{query}) AS keyword_rank"))
      .where(Arel.sql("search_vector @@ #{query}"))
      .order(Arel.sql('keyword_rank DESC, id ASC'))
      .limit(limit)
  }
end
