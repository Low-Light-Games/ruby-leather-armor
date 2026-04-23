# frozen_string_literal: true

class StripePlans
  class Plan
    attr_reader :key, :token_limit, :amount, :description, :stripe_product_id, :stripe_price_id

    def initialize(key:, attributes:)
      @key = key
      @token_limit = attributes.fetch("token_limit")
      @amount = attributes["amount"]
      @description = attributes["description"]
      @stripe_product_id = attributes["stripe_product_id"]
      @stripe_price_id = attributes["stripe_price_id"]
    end

    def free?
      key == "free"
    end
  end

  PLANS = begin
    raw = YAML.load_file(Rails.root.join("config/stripe_plans.yml"))
    raw.each_with_object({}) do |(key, attrs), memo|
      normalized = attrs.transform_keys(&:to_s)
      normalized["token_limit"] = normalized.fetch("token_limit").to_i
      memo[key.to_s] = Plan.new(key: key.to_s, attributes: normalized)
    end.freeze
  end

  PLAN_KEYS = PLANS.keys.freeze

  def self.fetch(plan_key)
    PLANS.fetch(plan_key.to_s)
  end

  def self.token_limit_for(plan_key)
    fetch(plan_key).token_limit
  end

  def self.find_by_price_id(price_id)
    return nil if price_id.blank?

    PLANS.values.find { |plan| plan.stripe_price_id == price_id }
  end
end
