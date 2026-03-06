# frozen_string_literal: true

class AiUsageRecord < ApplicationRecord
  belongs_to :adventure, optional: true
  belongs_to :user, optional: true
  belongs_to :ai_log, optional: true

  validates :model_id, presence: true
  validates :input_tokens, numericality: { greater_than_or_equal_to: 0 }
  validates :output_tokens, numericality: { greater_than_or_equal_to: 0 }
  validates :reasoning_tokens, numericality: { greater_than_or_equal_to: 0 }
  validates :total_tokens, numericality: { greater_than_or_equal_to: 0 }

  scope :by_model, ->(model_id) { where(model_id: model_id) }
  scope :for_adventure, ->(adventure_id) { where(adventure_id: adventure_id) }
  scope :for_user, ->(user_id) { where(user_id: user_id) }
  scope :for_pipeline, ->(pipeline_run_id) { where(pipeline_run_id: pipeline_run_id) }
  scope :in_period, ->(start_date, end_date) {
    where(created_at: start_date.beginning_of_day..end_date.end_of_day)
  }

  # Compute cost in microdollars using catalog pricing.
  # Reasoning tokens are billed at the output rate per OpenAI pricing.
  def self.compute_cost(model_id, input_tokens, output_tokens, reasoning_tokens = 0)
    meta = OpenaiModelCatalog.catalog[model_id] || {}
    input_rate = meta["input_cost"] || 0    # $/1M tokens
    output_rate = meta["output_cost"] || 0  # $/1M tokens

    # microdollars = tokens * rate_per_million (since rate is $/1M and 1M microdollars = $1)
    input_cost = (input_tokens * input_rate).round
    output_cost = ((output_tokens + reasoning_tokens) * output_rate).round

    {
      input_cost_microdollars: input_cost,
      output_cost_microdollars: output_cost,
      total_cost_microdollars: input_cost + output_cost
    }
  end
end
