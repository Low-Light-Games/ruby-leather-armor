# frozen_string_literal: true

# Executes all billing analytics aggregations for a given date range and
# optional filters, returning a plain data object consumed by
# Admin::BillingController.
#
# Usage:
#   result = BillingAnalyticsQuery.new(
#     start_date: Date.current.beginning_of_month,
#     end_date:   Date.current,
#     model:      params[:model],
#     adventure_id: params[:adventure_id],
#     user_id: params[:user_id]
#   ).call
#
#   result.totals       # → [count, input_tokens, output_tokens, ...]
#   result.by_model     # → AR relation
#   result.by_user      # → AR relation
#   result.by_adventure # → AR relation
#   result.by_day       # → AR relation
#   result.by_step      # → AR relation
class BillingAnalyticsQuery
  Result = Struct.new(:totals, :by_model, :by_user, :by_adventure, :by_day,
                       :by_step, :pipeline_count, :available_models, :available_users,
                       keyword_init: true)

  def initialize(start_date:, end_date:, model: nil, adventure_id: nil, user_id: nil)
    @start_date   = start_date
    @end_date     = end_date
    @model        = model
    @adventure_id = adventure_id
    @user_id      = user_id
  end

  def call
    scope = base_scope

    Result.new(
      totals:           fetch_totals(scope),
      by_model:         by_model(scope),
      by_user:          by_user(scope),
      by_adventure:     by_adventure(scope),
      by_day:           by_day(scope),
      by_step:          by_step(scope),
      pipeline_count:   pipeline_count(scope),
      available_models: available_models,
      available_users:  available_users,
    )
  end

  private

  def base_scope
    scope = AiUsageRecord.in_period(@start_date, @end_date)
    scope = scope.by_model(@model)            if @model.present?
    scope = scope.for_adventure(@adventure_id) if @adventure_id.present?
    scope = scope.for_user(@user_id)          if @user_id.present?
    scope
  end

  def fetch_totals(scope)
    scope.pick(
      Arel.sql("COUNT(*)"),
      Arel.sql("COALESCE(SUM(input_tokens), 0)"),
      Arel.sql("COALESCE(SUM(output_tokens), 0)"),
      Arel.sql("COALESCE(SUM(reasoning_tokens), 0)"),
      Arel.sql("COALESCE(SUM(total_tokens), 0)"),
      Arel.sql("COALESCE(SUM(total_cost_microdollars), 0)")
    )
  end

  def by_model(scope)
    scope.group(:model_id)
         .select("model_id",
                 "COUNT(*) AS call_count",
                 "SUM(input_tokens) AS sum_input",
                 "SUM(output_tokens) AS sum_output",
                 "SUM(reasoning_tokens) AS sum_reasoning",
                 "SUM(total_tokens) AS sum_total",
                 "SUM(total_cost_microdollars) AS sum_cost")
         .order("sum_cost DESC")
  end

  def by_user(scope)
    scope.where.not(user_id: nil)
         .group(:user_id)
         .select("user_id",
                 "COUNT(*) AS call_count",
                 "SUM(total_tokens) AS sum_total",
                 "SUM(total_cost_microdollars) AS sum_cost")
         .order("sum_cost DESC")
  end

  def by_adventure(scope)
    scope.where.not(adventure_id: nil)
         .group(:adventure_id)
         .select("adventure_id",
                 "COUNT(*) AS call_count",
                 "SUM(total_tokens) AS sum_total",
                 "SUM(total_cost_microdollars) AS sum_cost")
         .order("sum_cost DESC")
         .limit(50)
  end

  def by_day(scope)
    scope.group(Arel.sql("DATE(created_at)"))
         .select("DATE(created_at) AS day",
                 "COUNT(*) AS call_count",
                 "SUM(total_tokens) AS sum_total",
                 "SUM(total_cost_microdollars) AS sum_cost")
         .order("day DESC")
  end

  def by_step(scope)
    scope.where.not(event_type: [nil, ""])
         .group(:event_type)
         .select("event_type AS step_name",
                 "COUNT(*) AS call_count",
                 "SUM(total_tokens) AS sum_total",
                 "SUM(total_cost_microdollars) AS sum_cost",
                 "AVG(total_cost_microdollars) AS avg_cost")
         .order("sum_cost DESC")
  end

  def pipeline_count(scope)
    scope.where.not(registry_entry_uuid: [nil, ""])
         .distinct.count(:registry_entry_uuid)
  end

  def available_models
    AiUsageRecord.in_period(@start_date, @end_date)
                 .distinct.pluck(:model_id).sort
  end

  def available_users
    user_ids = AiUsageRecord.in_period(@start_date, @end_date)
                            .where.not(user_id: nil)
                            .distinct.pluck(:user_id)
    User.where(id: user_ids).order(:email)
  end
end
