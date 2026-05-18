# frozen_string_literal: true

module Admin
  class FeedbacksController < BaseController
    PER_PAGE = 50

    def index
      @feedbacks = Feedback.includes(:user).order(created_at: :desc)
      @page = [params[:page].to_i, 1].max
      @total_count = @feedbacks.count
      @total_pages = (@total_count.to_f / PER_PAGE).ceil
      @feedbacks = @feedbacks.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
    end

    def show
      @feedback = Feedback.includes(:user).find(params[:id])
    end

    private

    def require_admin
      unless current_user&.admin?
        redirect_to root_path, alert: "Unauthorized"
      end
    end
  end
end
