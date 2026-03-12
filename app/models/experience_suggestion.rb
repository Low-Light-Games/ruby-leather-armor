# frozen_string_literal: true

class ExperienceSuggestion < ApplicationRecord
  belongs_to :adventure

  validates :category, :source_step, presence: true

  scope :unreviewed, -> { where(reviewed: false) }
  scope :by_category, ->(cat) { where(category: cat) }
end
