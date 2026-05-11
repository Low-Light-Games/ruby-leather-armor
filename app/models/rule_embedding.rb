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
end
