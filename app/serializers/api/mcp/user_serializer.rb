# frozen_string_literal: true

module Api
  module Mcp
    class UserSerializer
      def self.call(user)
        {
          id: user.id,
          email: user.email,
          admin: user.admin,
          banned: user.banned,
          trusted: user.trusted,
          provider: user.provider,
          onboarding_state: user.onboarding_state,
          plan_key: user.plan_key,
          created_at: user.created_at,
          moderation_strikes: user.moderation_strikes
        }
      end
    end
  end
end
