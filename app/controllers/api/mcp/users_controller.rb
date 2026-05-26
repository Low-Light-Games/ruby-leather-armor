# frozen_string_literal: true

module Api
  module Mcp
    class UsersController < Api::BaseController
      def show
        render json: UserSerializer.call(User.find(params[:id]))
      end

      def find
        if params[:email].blank? && params[:id].blank?
          return render json: { error: "invalid_arguments", detail: "Provide email or id." }, status: :bad_request
        end

        scope = User.all
        scope = scope.for_email(params[:email]) if params[:email].present?
        scope = scope.where(id: params[:id])    if params[:id].present?
        user = scope.first
        return render_not_found("user not found") unless user

        render json: UserSerializer.call(user)
      end
    end
  end
end
