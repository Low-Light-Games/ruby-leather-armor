# frozen_string_literal: true

module DungeonMaster
  module Rolls
    # Code-driven d20 / damage dice for automated combat (world turn, reactive NPC lines in Mutations).
    #
    # Deliberately separate from {PlayerRolls}: that flow handles *player-submitted* roll text,
    # Take 10/20, dedupe, and AdventureLoop tagging. This module is pure RNG + PF-style math
    # when the pipeline rolls without a player prompt.
    module CombatDice
      module_function

      def roll_d20
        rand(1..20)
      end

      # PF-style attack: d20 + modifier vs AC.
      # @return [Hash] :d20, :total, :hit (boolean)
      def d20_attack_vs_ac(modifier:, ac:)
        d20 = roll_d20
        total = d20 + modifier.to_i
        { d20: d20, total: total, hit: total >= ac.to_i }
      end

      # Rolls "NdS+M" (e.g. 1d6+2). Unknown shape falls back to 1d4.
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
end
