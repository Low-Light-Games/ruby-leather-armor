# frozen_string_literal: true

class SessionUserPresenter
  def initialize(user:)
    @user = user
  end

  def to_h
    {
      id: user.id,
      email: user.email,
      admin: user.admin,
      plan_key: user.plan_key,
      has_billing_profile: user.stripe_profile.present?,
      onboarding_state: user.onboarding_state,
      banned: user.banned?,
      trusted: user.trusted?,
      moderation_strikes: user.moderation_strikes,
      combat_dice_strategy: user.combat_dice_strategy,
      usage: {
        current_tokens: user.monthly_usage_tokens,
        limit_tokens: user.monthly_usage_limit,
        percentage: user.usage_percentage,
        limit_reached: user.usage_limit_reached?,
        delinquent: user.stripe_profile&.delinquent? || false,
        grace_period_ends_at: user.stripe_profile&.grace_period_ends_at
      }
    }
  end

  private

  attr_reader :user
end
