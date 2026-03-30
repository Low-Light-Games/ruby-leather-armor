# frozen_string_literal: true

# Audit record created each time a user's input is flagged by the moderation API.
# Preserves the strike number at the time of the event and which categories fired.
class ModerationEvent < ApplicationRecord
  belongs_to :user

  validates :strike_number, presence: true, numericality: { only_integer: true, greater_than: 0 }

  scope :recent, -> { order(created_at: :desc) }
end
