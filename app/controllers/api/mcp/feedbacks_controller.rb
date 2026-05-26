# frozen_string_literal: true

module Api
  module Mcp
    class FeedbacksController < Api::BaseController
      MAX_LIMIT = 100
      DEFAULT_LIMIT = 25

      def index
        scope = Feedback.includes(:user).order(created_at: :desc)
        scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?
        scope = scope.where("created_at >= ?", Time.zone.parse(params[:since])) if params[:since].present?
        scope = scope.limit(clamped_limit)

        render json: scope.map { |f| serialize(f) }
      end

      private

      def clamped_limit
        n = params[:limit].to_i
        return DEFAULT_LIMIT if n <= 0

        [n, MAX_LIMIT].min
      end

      def serialize(feedback)
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
