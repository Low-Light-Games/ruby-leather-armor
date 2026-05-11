# frozen_string_literal: true

module CharacterStats
  module ActiveBuffResolverNumbers
    module_function

    UNIT_TO_HOURS = {
      "hours"   => 1.0,
      "minutes" => 1.0 / 60.0,
      "rounds"  => 1.0 / 600.0,
    }.freeze

    def duration_hours_from_formula(formula, level:)
      return nil unless formula.is_a?(Hash)

      multiplier = UNIT_TO_HOURS[formula["unit"]]
      return nil unless multiplier

      return formula["fixed"].to_f * multiplier if formula.key?("fixed")

      return formula["per_level"].to_f * level * multiplier if formula.key?("per_level") && level

      nil
    end

    def bonus_numeric_from_effect(effect, caster_level: nil)
      raw = effect["bonus"]

      return raw if raw.is_a?(Integer)

      return raw.to_i if raw.is_a?(Float)

      return scaled_formula_bonus(effect["bonus_formula"], caster_level) if effect["bonus_formula"].is_a?(Hash)

      return Integer(raw, 10) if raw.is_a?(String) && raw.match?(/\A-?\d+\z/)

      nil
    end

    def scaled_formula_bonus(bonus_formula, caster_level)
      base = bonus_formula["base"].to_i
      return base unless scales_with_caster_level?(bonus_formula, caster_level)

      scaled = base + (caster_level / bonus_formula["per_n_cl"].to_i)
      bonus_formula["max"] ? [scaled, bonus_formula["max"].to_i].min : scaled
    end

    def scales_with_caster_level?(bonus_formula, caster_level)
      caster_level && bonus_formula["per_n_cl"].to_i > 0
    end
  end
end
