# frozen_string_literal: true

class Adventure < ApplicationRecord
  belongs_to :user
  belongs_to :story
  belongs_to :current_location, class_name: "StoryLocation", optional: true

  has_many :adventure_sheets, dependent: :destroy
  has_many :adventure_messages, dependent: :destroy
  has_many :dm_logs, dependent: :nullify
  has_many :ai_logs, dependent: :nullify
  has_many :creature_sheets, dependent: :destroy

  DM_MODES = %w[standard].freeze

  validates :dm_mode, inclusion: { in: DM_MODES }, allow_nil: true

  def directed_dm?
    directed_dm == true
  end
end
