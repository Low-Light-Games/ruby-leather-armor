class Sheet < ApplicationRecord
  belongs_to :user

  has_many :adventures, dependent: :destroy

  validates :name, presence: true
  validates :strength, presence: true
  validates :intelligence, presence: true
  validates :dexterity, presence: true
  validates :constitution, presence: true
  validates :wisdom, presence: true
  validates :charisma, presence: true
end