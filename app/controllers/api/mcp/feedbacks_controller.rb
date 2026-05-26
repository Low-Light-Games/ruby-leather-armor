# frozen_string_literal: true

module Api
  module Mcp
    class FeedbacksController < Api::BaseController
      include ListParams

      def index
        scope = Feedback.includes(:user).order(created_at: :desc)
        scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?
        scope = scope.created_since(params[:since])
        scope = scope.limit(clamped_limit(default: 25, max: 100))

        render json: scope.map { |f| FeedbackSerializer.call(f) }
      end
    end
  end
end
