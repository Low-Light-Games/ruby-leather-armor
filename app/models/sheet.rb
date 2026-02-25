# frozen_string_literal: true

class Sheet < ApplicationRecord
  belongs_to :user

  has_many :adventure_sheets, dependent: :nullify

  validates :name, presence: true
  validates :strength, presence: true
  validates :intelligence, presence: true
  validates :dexterity, presence: true
  validates :constitution, presence: true
  validates :wisdom, presence: true
  validates :charisma, presence: true
  validates :level, numericality: { only_integer: true, greater_than: 0 }
end
