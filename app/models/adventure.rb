class Adventure < ApplicationRecord
  belongs_to :user
  belongs_to :sheet
  belongs_to :story_state

  validates :character_gold, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
