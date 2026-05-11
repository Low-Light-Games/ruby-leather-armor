# frozen_string_literal: true

module Combat
  module Dice
    module_function

    def roll_d20
      rand(1..20)
    end

    # @return [Hash] :d20, :total, :hit (boolean)
    def d20_attack_vs_ac(modifier:, ac:)
      d20 = roll_d20
      total = d20 + modifier.to_i
      { d20: d20, total: total, hit: total >= ac.to_i }
    end

    def roll_damage_expression(expr)
      s = expr.to_s.strip.downcase.gsub(/\s+/, "")
      m = s.match(/\A(\d+)d(\d+)([+-]\d+)?\z/i)
      unless m
        Rails.logger.warn("[CombatDice] Unrecognized damage expression #{expr.inspect}, defaulting to 1d4")
        return rand(1..4)
      end

      count = m[1].to_i
      sides = m[2].to_i
      mod = m[3] ? m[3].to_i : 0
      count.times.sum { rand(sides) + 1 } + mod
    end
  end
end
