# frozen_string_literal: true

class Adventure < ApplicationRecord
  belongs_to :user
  belongs_to :story

  has_many :adventure_sheets, dependent: :destroy
  has_many :adventure_messages, dependent: :destroy
  has_many :dm_logs, dependent: :destroy
  has_many :ai_logs, dependent: :destroy
  has_many :creature_sheets, dependent: :destroy
  has_many :encounters, dependent: :destroy
  has_many :locations, dependent: :destroy

  DM_MODES = %w[standard light].freeze

  validates :dm_mode, inclusion: { in: DM_MODES }, allow_nil: true

  def light_mode?
    dm_mode == "light"
  end

  def current_location
    locations.current.first
  end

  def active_encounter
    encounters.active.order(created_at: :desc).first
  end
end
