# frozen_string_literal: true

class Adventure < ApplicationRecord
  belongs_to :user
  belongs_to :story_state

  has_many :adventure_sheets, dependent: :destroy
  has_many :adventure_messages, dependent: :destroy
  has_many :dm_logs, dependent: :destroy
  has_many :ai_logs, dependent: :destroy
end
