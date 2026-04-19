# frozen_string_literal: true

class AdventureBattlefield < ApplicationRecord
  STATUSES = %w[active archived].freeze

  belongs_to :adventure

  validates :status, inclusion: { in: STATUSES }
  validates :topology, presence: true
  validates :version, numericality: { only_integer: true, greater_than: 0 }

  scope :active_for, ->(adventure_id) { where(adventure_id: adventure_id, status: "active") }

  def archive!
    update!(status: "archived", archived_at: Time.current)
  end
end
