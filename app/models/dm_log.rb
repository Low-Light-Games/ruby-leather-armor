class DmLog < ApplicationRecord
  belongs_to :adventure, optional: true
  belongs_to :user

  validates :content, presence: true

  scope :recent_first, -> { order(created_at: :desc) }
end
