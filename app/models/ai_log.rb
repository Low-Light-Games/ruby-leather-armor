class AiLog < ApplicationRecord
  belongs_to :adventure
  belongs_to :player_message, class_name: "AdventureMessage", optional: true

  CALL_TYPES = %w[
    triage dm_query intent ruling evaluate narrate
    micro_context_update macro_narrative_update
  ].freeze

  # Legacy types kept for backward compatibility with existing log rows
  LEGACY_CALL_TYPES = %w[
    sanitization dm_response roll_response
    triage_merged classification
    scene_tracker story_chronicler narrator action_needs
  ].freeze

  DM_SERVICES = %w[standard].freeze

  validates :call_type, presence: true, inclusion: { in: CALL_TYPES + LEGACY_CALL_TYPES }
  validates :prompt_summary, presence: true
  validates :status, presence: true, inclusion: { in: %w[success parse_fallback parse_error api_error token_budget_exceeded] }
  validates :dm_service, inclusion: { in: DM_SERVICES }, allow_nil: true

  scope :recent_first, -> { order(created_at: :desc) }
end
