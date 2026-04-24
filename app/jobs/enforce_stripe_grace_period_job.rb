# frozen_string_literal: true

class EnforceStripeGracePeriodJob < ApplicationJob
  queue_as :default

  def perform
    UserStripeProfile.grace_expired.find_each do |profile|
      profile.update!(
        plan_key: "free",
        delinquent_since: nil,
        grace_period_ends_at: nil
      )
    end
  end
end
