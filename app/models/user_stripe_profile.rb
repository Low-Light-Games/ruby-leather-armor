# frozen_string_literal: true

class UserStripeProfile < ApplicationRecord
  belongs_to :user

  validates :plan_key, inclusion: { in: StripePlans::PLAN_KEYS }

  scope :grace_expired, -> { where.not(grace_period_ends_at: nil).where("grace_period_ends_at < ?", Time.current) }

  def delinquent?
    grace_period_ends_at.present? && grace_period_ends_at > Time.current
  end

  def grace_expired?
    grace_period_ends_at.present? && grace_period_ends_at <= Time.current
  end

  def effective_plan_key
    grace_expired? ? "free" : plan_key
  end
end
