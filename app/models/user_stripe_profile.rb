# frozen_string_literal: true

class UserStripeProfile < ApplicationRecord
  belongs_to :user

  validates :plan_key, inclusion: { in: StripePlans::PLAN_KEYS }
end
