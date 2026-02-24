class Story < ApplicationRecord
  has_many :story_states, dependent: :destroy

  validates :title, presence: true
  validates :preview, presence: true
  validates :premise, presence: true
end
