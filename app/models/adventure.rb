# frozen_string_literal: true

class Adventure < ApplicationRecord
  belongs_to :user
  belongs_to :story
  belongs_to :current_location, class_name: "StoryLocation", optional: true

  has_many :adventure_sheets, dependent: :destroy
  has_many :adventure_messages, dependent: :destroy
  has_many :dm_logs, dependent: :nullify
  has_many :play_logs, dependent: :nullify
  has_many :adventure_loops, dependent: :nullify
  has_many :pipeline_registry_entries, dependent: :destroy
  has_many :pipelines, dependent: :destroy
  has_many :creature_sheets, dependent: :destroy
  has_many :story_npcs, dependent: :destroy
  has_many :story_clues, dependent: :destroy

  scope :kept,      -> { where(discarded_at: nil) }
  scope :discarded, -> { where.not(discarded_at: nil) }

  def discard!
    update!(discarded_at: Time.current)
  end

  def discarded?
    discarded_at.present?
  end

  def directed_dm?
    directed_dm == true
  end

  def skip_world_sanity_check?
    skip_world_sanity_check == true
  end

  def effective_dm_setting(key)
    local = dm_settings[key.to_s]
    return local unless local.nil?

    DmConfig.instance.get(key)
  end
end
