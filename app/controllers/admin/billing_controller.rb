# frozen_string_literal: true

module Admin
  class BillingController < BaseController

    def show
      @start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : Date.current.beginning_of_month
      @end_date   = params[:end_date].present? ? Date.parse(params[:end_date]) : Date.current

      analytics = BillingAnalyticsQuery.new(
        start_date:   @start_date,
        end_date:     @end_date,
        model:        params[:model],
        adventure_id: params[:adventure_id],
        user_id:      params[:user_id]
      ).call

      @totals          = analytics.totals
      @by_model        = analytics.by_model
      @by_user         = analytics.by_user
      @users_by_id     = User.where(id: @by_user.map(&:user_id)).index_by(&:id)
      @by_adventure    = analytics.by_adventure
      @by_day          = analytics.by_day
      @by_step         = analytics.by_step
      @available_models = analytics.available_models
      @available_users  = analytics.available_users

      total_cost        = @totals[5]
      @pipeline_count   = analytics.pipeline_count
      @avg_per_pipeline = @pipeline_count > 0 ? (total_cost.to_f / @pipeline_count).round : 0
      @avg_per_call     = @totals[0] > 0 ? (total_cost.to_f / @totals[0]).round : 0

      render layout: 'admin'
    end

    private

    def require_admin
      unless current_user&.admin?
        redirect_to root_path, alert: "Unauthorized"
      end
    end
  end
end
