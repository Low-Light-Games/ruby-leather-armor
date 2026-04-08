# frozen_string_literal: true

# Registry row for one async DM pipeline execution: correlation id, status, timing,
# and links to related play logs and adventure loops. Not the in-memory pipeline engine.
class PipelineRegistryEntry < ApplicationRecord
  belongs_to :adventure
  belongs_to :player_message, class_name: "AdventureMessage", optional: true

  has_many :play_logs, primary_key: :registry_entry_uuid, foreign_key: :registry_entry_uuid
  has_many :adventure_loops, primary_key: :registry_entry_uuid, foreign_key: :registry_entry_uuid

  STATUSES = %w[running paused completed errored].freeze

  validates :registry_entry_uuid, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :started_at, presence: true

  scope :recent_first, -> { order(started_at: :desc) }

  def self.active_for?(adventure)
    where(adventure: adventure, status: "running")
      .where("started_at > ?", 15.minutes.ago)
      .exists?
  end
end
