# frozen_string_literal: true

module DungeonMaster
  module Steps
    module Phases
      class MechEvalDomainResult
        def initialize(domain:, player_rolls:, npc_actions:, consequences:, mechanical_summary:)
          @domain = domain
          @player_rolls = player_rolls
          @npc_actions = npc_actions
          @consequences = consequences
          @mechanical_summary = mechanical_summary.to_s
        end

        def empty?
          @player_rolls.empty? && @npc_actions.empty? && @consequences.empty? && @mechanical_summary.blank?
        end

        def to_h
          {
            domain: @domain,
            player_rolls: @player_rolls,
            npc_actions: @npc_actions,
            consequences: @consequences,
            mechanical_summary: @mechanical_summary
          }
        end
      end
    end
  end
end
