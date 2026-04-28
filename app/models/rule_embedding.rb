# frozen_string_literal: true

# A pre-computed embedding for one rule entry from
# `app/services/dungeon_master/rules/entries/*.yml`.
#
# Written by the `dungeon_master:rules:embed` rake task; read by
# `DungeonMaster::Rules::Lookup` via pgvector cosine similarity. Replaces
# the static rules-manifest dump that previously rode along with every
# beacon / mechanical_evaluation prompt.
#
# Single-writer invariant: the rake task is the only writer. The
# pipeline reads only.
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
end
