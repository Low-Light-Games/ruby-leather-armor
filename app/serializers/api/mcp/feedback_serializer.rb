# frozen_string_literal: true

module Api
  module Mcp
    class FeedbackSerializer
      def self.call(feedback)
        {
          id: feedback.id,
          user_id: feedback.user_id,
          user_email: feedback.user&.email,
          body: feedback.body,
          created_at: feedback.created_at
        }
      end
    end
  end
end
