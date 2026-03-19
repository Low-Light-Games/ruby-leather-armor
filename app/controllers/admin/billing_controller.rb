# frozen_string_literal: true

module Admin
  class BillingController < BaseController

    def show
      @start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : Date.current.beginning_of_month
      @end_date = params[:end_date].present? ? Date.parse(params[:end_date]) : Date.current

      scope = AiUsageRecord.in_period(@start_date, @end_date)
      scope = scope.by_model(params[:model]) if params[:model].present?
      scope = scope.for_adventure(params[:adventure_id]) if params[:adventure_id].present?
      scope = scope.for_user(params[:user_id]) if params[:user_id].present?

      @totals = scope.pick(
        Arel.sql("COUNT(*)"),
        Arel.sql("COALESCE(SUM(input_tokens), 0)"),
        Arel.sql("COALESCE(SUM(output_tokens), 0)"),
        Arel.sql("COALESCE(SUM(reasoning_tokens), 0)"),
        Arel.sql("COALESCE(SUM(total_tokens), 0)"),
        Arel.sql("COALESCE(SUM(total_cost_microdollars), 0)")
      )

      @by_model = scope.group(:model_id)
                       .select(
                         "model_id",
                         "COUNT(*) AS call_count",
                         "SUM(input_tokens) AS sum_input",
                         "SUM(output_tokens) AS sum_output",
                         "SUM(reasoning_tokens) AS sum_reasoning",
                         "SUM(total_tokens) AS sum_total",
                         "SUM(total_cost_microdollars) AS sum_cost"
                       )
                       .order("sum_cost DESC")

      @by_user = scope.where.not(user_id: nil)
                      .group(:user_id)
                      .select(
                        "user_id",
                        "COUNT(*) AS call_count",
                        "SUM(total_tokens) AS sum_total",
                        "SUM(total_cost_microdollars) AS sum_cost"
                      )
                      .order("sum_cost DESC")
      user_ids = @by_user.map(&:user_id)
      @users_by_id = User.where(id: user_ids).index_by(&:id)

      @by_adventure = scope.where.not(adventure_id: nil)
                           .group(:adventure_id)
                           .select(
                             "adventure_id",
                             "COUNT(*) AS call_count",
                             "SUM(total_tokens) AS sum_total",
                             "SUM(total_cost_microdollars) AS sum_cost"
                           )
                           .order("sum_cost DESC")
                           .limit(50)

      @by_day = scope.group(Arel.sql("DATE(created_at)"))
                     .select(
                       "DATE(created_at) AS day",
                       "COUNT(*) AS call_count",
                       "SUM(total_tokens) AS sum_total",
                       "SUM(total_cost_microdollars) AS sum_cost"
                     )
                     .order("day DESC")

      # Averages
      pipeline_count = scope.where.not(pipeline_run_id: [nil, ""])
                            .distinct.count(:pipeline_run_id)
      total_cost = @totals[5]
      @avg_per_pipeline = pipeline_count > 0 ? (total_cost.to_f / pipeline_count).round : 0
      @pipeline_count = pipeline_count
      @avg_per_call = @totals[0] > 0 ? (total_cost.to_f / @totals[0]).round : 0

      @by_step = scope.where.not(event_type: [nil, ""])
                      .group(:event_type)
                      .select(
                        "event_type AS step_name",
                        "COUNT(*) AS call_count",
                        "SUM(total_tokens) AS sum_total",
                        "SUM(total_cost_microdollars) AS sum_cost",
                        "AVG(total_cost_microdollars) AS avg_cost"
                      )
                      .order("sum_cost DESC")

      @available_models = AiUsageRecord.in_period(@start_date, @end_date)
                                       .distinct.pluck(:model_id).sort
      @available_users = User.where(id:
        AiUsageRecord.in_period(@start_date, @end_date)
                     .where.not(user_id: nil)
                     .distinct.pluck(:user_id)
      ).order(:email)

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
