# frozen_string_literal: true

# A durable narrative fact about the world of a single adventure, written
# by the Loremaster AI step and read by the World Consistency Check via
# pgvector cosine similarity.
#
# This store replaces micro-contexts as the dynamic-state input to
# `sanity_checker_world` (see plan: narrative facts store for world
# sanity). Loremaster is the sole writer; no other pipeline step, admin
# tool, or background job mutates this table (§18 single-writer invariant).
class AdventureNarrativeFact < ApplicationRecord
  KINDS      = %w[event state entity].freeze
  POLARITIES = %w[asserts negates].freeze
  SOURCES    = %w[seed loremaster].freeze

  belongs_to :adventure
  belongs_to :introduced_at_loop,
             class_name: "AdventureLoop",
             foreign_key: :introduced_at_loop_id,
             optional: true
  belongs_to :invalidated_at_loop,
             class_name: "AdventureLoop",
             foreign_key: :invalidated_at_loop_id,
             optional: true
  belongs_to :invalidated_by_fact,
             class_name: "AdventureNarrativeFact",
             foreign_key: :invalidated_by_fact_id,
             optional: true

  has_neighbors :embedding, dimensions: 1536

  validates :text,     presence: true
  validates :kind,     inclusion: { in: KINDS }
  validates :polarity, inclusion: { in: POLARITIES }
  validates :source,   inclusion: { in: SOURCES }

  scope :active,      -> { where(invalidated_at_loop_id: nil) }
  scope :invalidated, -> { where.not(invalidated_at_loop_id: nil) }
  scope :for_adventure, ->(adventure) { where(adventure_id: adventure.id) }

  def active?
    invalidated_at_loop_id.nil?
  end
end
