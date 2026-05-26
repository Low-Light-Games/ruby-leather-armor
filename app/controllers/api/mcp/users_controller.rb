# frozen_string_literal: true

module Api
  module Mcp
    class UsersController < Api::BaseController
      def show
        render json: serialize(User.find(params[:id]))
      end

      def find
        if params[:email].blank? && params[:id].blank?
          return render json: { error: "invalid_arguments", detail: "Provide email or id." }, status: :bad_request
        end

        scope = User.all
        scope = scope.where("LOWER(email) = ?", params[:email].downcase) if params[:email].present?
        scope = scope.where(id: params[:id]) if params[:id].present?
        user = scope.first
        return render_not_found("user not found") unless user

        render json: serialize(user)
      end

      private

      def serialize(user)
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
