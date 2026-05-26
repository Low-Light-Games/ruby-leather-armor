# frozen_string_literal: true

class Feedback < ApplicationRecord
  belongs_to :user, optional: true

  validates :body, presence: true, length: { maximum: 2000 }

  scope :created_since, ->(time) {
    parsed = time.is_a?(String) ? Time.zone.parse(time) : time
    parsed ? where("created_at >= ?", parsed) : all
  }
end
