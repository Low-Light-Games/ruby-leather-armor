class StoryState < ApplicationRecord
  belongs_to :story

  has_many :adventures, dependent: :destroy

  validates :description, presence: true

  scope :kept, -> { where(discarded_at: nil) }
  scope :discarded, -> { where.not(discarded_at: nil) }

  def discard!
    update!(discarded_at: Time.current)
  end

  def discarded?
    discarded_at.present?
  end
end
