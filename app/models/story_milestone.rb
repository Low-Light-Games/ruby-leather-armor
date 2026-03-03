# frozen_string_literal: true

class StoryMilestone < ApplicationRecord
  belongs_to :story

  SOURCES = %w[manual enricher].freeze

  validates :title, presence: true
  validates :description, presence: true
  validates :source, inclusion: { in: SOURCES }
end
