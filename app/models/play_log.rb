class PlayLog < ApplicationRecord
  belongs_to :adventure, optional: true
  belongs_to :player_message, class_name: "AdventureMessage", optional: true
  belongs_to :ai_usage_record, optional: true

  PIPELINE_EVENT_TYPES = %w[
    capability_rejection world_check_failure
    intake_rejection
    queue_paused queue_interrupted queue_completed
    auto_success_filter duplicate_roll_warning
    pipeline_abandoned
    harbinger warmaster
    pipeline_error
  ].freeze

  EVENT_TYPES = (DungeonMaster::StepRegistry.all_call_types + PIPELINE_EVENT_TYPES).freeze

  DM_SERVICES = %w[standard].freeze

  STATUSES = %w[success parse_fallback parse_error api_error token_budget_exceeded logging_error pipeline_event].freeze

  validates :event_type, presence: true
  validate :warn_unknown_event_type
  validates :prompt_summary, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :dm_service, inclusion: { in: DM_SERVICES }, allow_nil: true

  scope :recent_first, -> { order(created_at: :desc) }

  private

  def warn_unknown_event_type
    return if event_type.blank?

    unless event_type.in?(EVENT_TYPES)
      Rails.logger.warn("[PlayLog] Unknown event_type '#{event_type}' — saving anyway. " \
                        "Add it to StepRegistry or PIPELINE_EVENT_TYPES to suppress this warning.")
    end
  end
end
