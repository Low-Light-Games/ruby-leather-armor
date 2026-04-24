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

    def to_h
      {
        key: key,
        token_limit: token_limit,
        amount: amount,
        description: description,
        stripe_product_id: stripe_product_id,
        stripe_price_id: stripe_price_id
      }
    end
  end

  PLANS = StripePlansConfigLoader.load

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
