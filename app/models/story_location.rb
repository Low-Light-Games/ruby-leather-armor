# frozen_string_literal: true

class StoryLocation < ApplicationRecord
  belongs_to :story

  has_many :story_npcs, foreign_key: :location_id, dependent: :nullify
  has_many :story_clues, foreign_key: :location_id, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :story_id }
end
