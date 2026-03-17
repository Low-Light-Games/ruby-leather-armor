# frozen_string_literal: true

class PipelineRun < ApplicationRecord
  belongs_to :adventure
  belongs_to :player_message, class_name: "AdventureMessage", optional: true

  has_many :play_logs, primary_key: :pipeline_run_id, foreign_key: :pipeline_run_id
  has_many :adventure_loops, primary_key: :pipeline_run_id, foreign_key: :pipeline_run_id

  STATUSES = %w[running paused completed errored].freeze

  validates :pipeline_run_id, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :started_at, presence: true

  scope :recent_first, -> { order(started_at: :desc) }


end
