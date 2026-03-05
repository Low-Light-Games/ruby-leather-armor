class AiLog < ApplicationRecord
  belongs_to :adventure, optional: true
  belongs_to :player_message, class_name: "AdventureMessage", optional: true

  CALL_TYPES = %w[
    sanitize classify dm_query sequencer player_interpreter beacon
    mechanical_evaluation roll_qualifier sanity_checker sanity_checker_world
    verdict time_keeper chronicler narrate
    micro_context_update macro_narrative_update
    edge_pipeline encounter_expand creature_generation
  ].freeze

  # Legacy types kept for backward compatibility with existing log rows
  LEGACY_CALL_TYPES = %w[
    triage evaluate ruling intent dispatcher capability_guardrail
    sanitization dm_response roll_response
    triage_merged classification
    scene_tracker story_chronicler narrator action_needs
  ].freeze

  DM_SERVICES = %w[standard].freeze

  STATUSES = %w[success parse_fallback parse_error api_error token_budget_exceeded logging_error].freeze

  validates :call_type, presence: true, inclusion: { in: CALL_TYPES + LEGACY_CALL_TYPES }
  validates :prompt_summary, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :dm_service, inclusion: { in: DM_SERVICES }, allow_nil: true

  scope :recent_first, -> { order(created_at: :desc) }
end
