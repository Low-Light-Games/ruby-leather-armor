class PlayLog < ApplicationRecord
  belongs_to :adventure, optional: true
  belongs_to :player_message, class_name: "AdventureMessage", optional: true
  belongs_to :ai_usage_record, optional: true

  PIPELINE_EVENT_TYPES = %w[
    capability_rejection world_check_failure
    intake_rejection
    queue_paused queue_interrupted queue_completed
    auto_success_filter duplicate_roll_warning
    ownership_guard
    pipeline_abandoned
    harbinger warmaster
    battlefield_version_mismatch
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
  scope :for_adventure, ->(adventure_id) { where(adventure_id: adventure_id) }
  scope :with_status, ->(status) { where(status: status) }
  scope :with_event_type, ->(event_type) { where(event_type: event_type) }
  scope :with_registry_entry_uuid, ->(uuid) { where(registry_entry_uuid: uuid) }
  scope :with_registry_entry_uuid_present, -> { where.not(registry_entry_uuid: [nil, ""]) }
  scope :for_registry_entry_uuids, ->(uuids) { where(registry_entry_uuid: uuids) }

  def self.recent_registry_entry_uuids_for_adventure(adventure_id, limit: 5)
    for_adventure(adventure_id)
      .with_registry_entry_uuid_present
      .recent_first
      .pluck(:registry_entry_uuid)
      .uniq
      .first(limit)
  end

  private

  def warn_unknown_event_type
    return if event_type.blank?

    unless event_type.in?(EVENT_TYPES)
      Rails.logger.warn("[PlayLog] Unknown event_type '#{event_type}' — saving anyway. " \
                        "Add it to StepRegistry or PIPELINE_EVENT_TYPES to suppress this warning.")
    end
  end
end
