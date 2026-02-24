class Story < ApplicationRecord
  has_many :story_states, -> { kept.order(position: :asc) }, dependent: :destroy

  validates :title, presence: true
  validates :preview, presence: true
  validates :premise, presence: true

  scope :kept, -> { where(discarded_at: nil) }
  scope :discarded, -> { where.not(discarded_at: nil) }

  def discard!
    update!(discarded_at: Time.current)
  end

  def discarded?
    discarded_at.present?
  end
end
