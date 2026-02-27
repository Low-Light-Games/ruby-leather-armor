class AdventureMessage < ApplicationRecord
  belongs_to :adventure

  validates :role, presence: true, inclusion: { in: %w[player dm system] }
  validates :content, presence: true
  validates :message_type, presence: true, inclusion: {
    in: %w[narrative sanitization_fail adventure_complete roll_request roll_result]
  }

  scope :chronological, -> { order(created_at: :asc) }
end
