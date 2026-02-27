# frozen_string_literal: true

class EncounterParticipant < ApplicationRecord
  belongs_to :encounter
  belongs_to :adventure_sheet, optional: true
  belongs_to :creature_sheet, optional: true

  TEAMS = %w[player enemy neutral].freeze

  validates :team, presence: true, inclusion: { in: TEAMS }
  validate :must_have_one_sheet

  def name
    adventure_sheet&.name || creature_sheet&.name || "Unknown"
  end

  def player?
    team == "player"
  end

  def enemy?
    team == "enemy"
  end

  def alive?
    is_active && current_hp > 0
  end

  def distance_to(other)
    dx = position_x - other.position_x
    dy = position_y - other.position_y
    Math.sqrt(dx**2 + dy**2) * 5.0 # 1 square = 5 feet
  end

  private

  def must_have_one_sheet
    if adventure_sheet_id.blank? && creature_sheet_id.blank?
      errors.add(:base, "Must reference either an adventure_sheet or a creature_sheet")
    end
  end
end
