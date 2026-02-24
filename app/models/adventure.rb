class Adventure < ApplicationRecord
  belongs_to :user
  belongs_to :sheet
  belongs_to :story_state

  has_many :adventure_messages, dependent: :destroy
  has_many :dm_logs, dependent: :destroy
  has_many :ai_logs, dependent: :destroy

  validates :character_gold, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
