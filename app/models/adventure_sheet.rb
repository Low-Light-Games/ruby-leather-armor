# frozen_string_literal: true

class AdventureSheet < ApplicationRecord
  belongs_to :adventure
  belongs_to :sheet, optional: true # reference to the original player sheet (nullable)

  validates :name, presence: true
  validates :strength, :intelligence, :dexterity, :constitution, :wisdom, :charisma, presence: true
  validates :level, numericality: { only_integer: true, greater_than: 0 }
  validates :gold, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
