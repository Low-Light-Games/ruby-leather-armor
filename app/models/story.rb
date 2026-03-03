class Story < ApplicationRecord
  has_many :adventures, dependent: :destroy
  has_many :story_locations, dependent: :destroy
  has_many :encounter_tables, dependent: :destroy
  has_many :story_npcs, dependent: :destroy
  has_many :story_clues, dependent: :destroy
  has_many :story_milestones, dependent: :destroy

  accepts_nested_attributes_for :story_locations, allow_destroy: true
  accepts_nested_attributes_for :encounter_tables, allow_destroy: true
  accepts_nested_attributes_for :story_npcs, allow_destroy: true
  accepts_nested_attributes_for :story_clues, allow_destroy: true
  accepts_nested_attributes_for :story_milestones, allow_destroy: true

  validates :title, presence: true
  validates :preview, presence: true
  validates :premise, presence: true

  def starting_location
    story_locations.find_by(starting: true)
  end

  scope :kept, -> { where(discarded_at: nil) }
  scope :discarded, -> { where.not(discarded_at: nil) }

  def discard!
    update!(discarded_at: Time.current)
  end

  def discarded?
    discarded_at.present?
  end
end
