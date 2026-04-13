class AdventureMessage < ApplicationRecord
  belongs_to :adventure

  validates :role, presence: true, inclusion: { in: %w[player dm system] }
  validates :content, presence: true
  validates :message_type, presence: true, inclusion: {
    in: %w[narrative sanitization_fail adventure_complete player_death roll_request roll_result
           initiative_request initiative_result dm_query moderation_flagged usage_limit]
  }

  scope :chronological, -> { order(created_at: :asc) }
  scope :newest_first, -> { order(created_at: :desc) }
  scope :from_players, -> { where(role: "player") }
  scope :for_message_types, ->(types) { where(message_type: types) }
end
