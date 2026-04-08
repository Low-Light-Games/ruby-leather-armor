# frozen_string_literal: true

class AdventureLoop < ApplicationRecord
  belongs_to :adventure, optional: true

  STATUSES = %w[pending resolving paused resolved encounter social_scene errored].freeze

  validates :registry_entry_uuid, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :for_registry_entry, ->(uuid) { where(registry_entry_uuid: uuid) }
  scope :paused, -> { where(status: "paused") }

  # Prior actions in the same registry entry (lower sequence_index), for progressive_continuity prompts.
  def self.prior_pipeline_outcomes_before(registry_entry_uuid:, current_loop:)
    return [] if registry_entry_uuid.blank? || current_loop.nil?

    for_registry_entry(registry_entry_uuid)
      .where("sequence_index < ?", current_loop.sequence_index)
      .order(:sequence_index)
      .filter_map { |l| l.get("pipeline_outcome") }
  end

  # ---- Tag helpers (boolean flags) ----

  def tagged?(name)
    tags[name.to_s] == true
  end

  # ---- Data helpers (key-value store) ----

  def get(key)
    data[key.to_s]
  end

  # ---- Batch helpers (minimize DB writes) ----

  def batch_update!(new_tags: nil, new_data: nil, new_status: nil, timeline_entry: nil)
    self.tags = tags.merge(new_tags) if new_tags
    self.data = data.merge(new_data) if new_data
    self.status = new_status if new_status
    self.timeline = timeline + [timeline_entry] if timeline_entry
    save!
  end

  # ---- Timeline helpers ----

  def log_step(step_name, summary)
    entry = { "step" => step_name.to_s, "summary" => summary.to_s.truncate(200), "at" => Time.current.iso8601 }
    self.timeline = timeline + [entry]
    save!
  end

  # ---- Prompt summary (concise one-liner for template injection) ----

  def prompt_summary
    parts = []
    parts << "Category: #{category}" if category.present?
    active_tags = tags.select { |_, v| v == true }.keys
    parts << "Tags: #{active_tags.join(', ')}" if active_tags.any?
    parts << "Resolution: #{data['resolution_method']}" if data["resolution_method"].present?
    parts.join(" | ")
  end
end
