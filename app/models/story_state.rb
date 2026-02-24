class StoryState < ApplicationRecord
  belongs_to :story

  has_many :adventures, dependent: :destroy

  validates :description, presence: true
end
