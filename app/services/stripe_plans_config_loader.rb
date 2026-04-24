# frozen_string_literal: true

class StripePlansConfigLoader
  def self.load
    raw = YAML.load_file(Rails.root.join("config/stripe_plans.yml"))
    raw.each_with_object({}) do |(key, attrs), memo|
      normalized = attrs.transform_keys(&:to_s)
      normalized["token_limit"] = normalized.fetch("token_limit").to_i
      memo[key.to_s] = StripePlans::Plan.new(key: key.to_s, attributes: normalized)
    end.freeze
  end
end
