# frozen_string_literal: true

module DungeonMaster
  module Mutations
    class NpcActionSummary
      def self.format(sheet:, npc_actions:)
        return "(no NPC actions)" if npc_actions.blank?

        player_ac = sheet.derived_stats.fetch("ac")
        results = npc_actions.map do |action|
          modifier = (action[:modifier] || 0).to_i
          atk = Rolls::CombatDice.d20_attack_vs_ac(modifier: modifier, ac: player_ac)
          "#{action[:actor]} #{action[:action]} -> rolled #{atk[:d20]} + #{modifier} = #{atk[:total]} " \
            "vs AC #{player_ac}: #{atk[:hit] ? 'HIT' : 'MISS'}"
        end

        results.join("\n")
      end
    end
  end
end
