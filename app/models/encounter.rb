# frozen_string_literal: true

class Encounter < ApplicationRecord
  belongs_to :adventure

  has_many :encounter_participants, dependent: :destroy

  STATUSES = %w[pending active completed].freeze

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :round_number, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :grid_width, :grid_height, numericality: { only_integer: true, greater_than: 0 }

  scope :active, -> { where(status: "active") }

  def active?
    status == "active"
  end

  def completed?
    status == "completed"
  end

  def current_participant
    ordered_participants[current_turn_index]
  end

  def ordered_participants
    encounter_participants.where(is_active: true).order(initiative: :desc, id: :asc)
  end

  def advance_turn!
    participants = ordered_participants.to_a
    return if participants.empty?

    next_index = (current_turn_index + 1) % participants.size
    new_round = next_index == 0 ? round_number + 1 : round_number

    update!(current_turn_index: next_index, round_number: new_round)
  end
end
