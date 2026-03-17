class AiLog < ApplicationRecord
  belongs_to :adventure, optional: true
  belongs_to :player_message, class_name: "AdventureMessage", optional: true
  belongs_to :ai_usage_record, optional: true

  CALL_TYPES = DungeonMaster::StepRegistry.all_call_types.freeze

  DM_SERVICES = %w[standard].freeze

  STATUSES = %w[success parse_fallback parse_error api_error token_budget_exceeded logging_error].freeze

  validates :call_type, presence: true
  validate :warn_unknown_call_type
  validates :prompt_summary, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :dm_service, inclusion: { in: DM_SERVICES }, allow_nil: true

  scope :recent_first, -> { order(created_at: :desc) }

  private

  def warn_unknown_call_type
    return if call_type.blank?

    unless call_type.in?(CALL_TYPES)
      Rails.logger.warn("[AiLog] Unknown call_type '#{call_type}' — saving anyway. " \
                        "Add it to StepRegistry to suppress this warning.")
    end
  end
end
