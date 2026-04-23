# frozen_string_literal: true

class SubscriptionPlansPresenter
  def initialize(user:)
    @user = user
  end

  def current_plan_key
    user&.plan_key || "free"
  end

  def plans_payload
    StripePlans::PLAN_KEYS
      .map { |key| StripePlans.fetch(key) }
      .reject(&:free?)
      .map(&:to_h)
  end

  private

  attr_reader :user
end
