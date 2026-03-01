class AiLog < ApplicationRecord
  belongs_to :adventure

  CALL_TYPES = %w[
    sanitization dm_response roll_response
    triage_merged classification
    scene_tracker story_chronicler narrator action_needs
  ].freeze

  DM_SERVICES = %w[standard].freeze

  validates :call_type, presence: true, inclusion: { in: CALL_TYPES }
  validates :prompt_summary, presence: true
  validates :status, presence: true, inclusion: { in: %w[success parse_fallback parse_error api_error] }
  validates :dm_service, inclusion: { in: DM_SERVICES }, allow_nil: true

  scope :recent_first, -> { order(created_at: :desc) }
end
