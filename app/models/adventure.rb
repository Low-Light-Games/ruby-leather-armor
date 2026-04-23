# frozen_string_literal: true

class Adventure < ApplicationRecord
  belongs_to :user
  belongs_to :story
  belongs_to :current_location, class_name: "StoryLocation", optional: true

  has_many :adventure_sheets, dependent: :destroy
  has_many :adventure_messages, dependent: :destroy
  has_many :play_logs, dependent: :nullify
  has_many :adventure_loops, dependent: :nullify
  has_many :pipeline_registry_entries, dependent: :destroy
  has_many :pipelines, dependent: :destroy
  has_many :creature_sheets, dependent: :destroy
  has_many :adventure_battlefields, dependent: :destroy
  has_many :story_npcs, dependent: :destroy
  has_many :story_clues, dependent: :destroy
  has_many :experience_suggestions, dependent: :destroy
  has_many :adventure_narrative_facts, dependent: :destroy

  include Contextable

  scope :kept,      -> { where(discarded_at: nil) }
  scope :discarded, -> { where.not(discarded_at: nil) }
  scope :admin_index_includes, -> { includes(:user, :story, :current_location, :adventure_sheets) }
  scope :recently_updated, -> { order(updated_at: :desc) }
  scope :for_story, ->(story_id) { where(story_id: story_id) }

  def discard!
    update!(discarded_at: Time.current)
  end

  def discarded?
    discarded_at.present?
  end

  def ended?
    ended_at.present?
  end

  def mark_ended!(reason:)
    reason = reason.to_s
    now = Time.current
    updated = self.class.where(id: id, ended_at: nil)
                        .update_all(ended_at: now, end_reason: reason, updated_at: now)
    reload if updated.positive?
    updated.positive?
  end

  def directed_dm?
    directed_dm == true
  end

  def skip_world_sanity_check?
    skip_world_sanity_check == true
  end

  def combat_active?
    ctx = combat_context
    ctx.is_a?(Hash) && ctx["active"] == true && Array(ctx["participants"]).any?
  end

  def effective_dm_setting(key)
    local = dm_settings[key.to_s]
    return local unless local.nil?

    DmConfig.instance.get(key)
  end
end
