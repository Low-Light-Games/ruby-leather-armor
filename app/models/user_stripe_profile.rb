# frozen_string_literal: true

class UserStripeProfile < ApplicationRecord
  PLAN_KEYS = %w[free novice scout adventurer].freeze

  belongs_to :user

  validates :plan_key, inclusion: { in: PLAN_KEYS }
end
