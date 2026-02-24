class DmLog < ApplicationRecord
  belongs_to :adventure
  belongs_to :user

  validates :content, presence: true

  scope :recent_first, -> { order(created_at: :desc) }
end
