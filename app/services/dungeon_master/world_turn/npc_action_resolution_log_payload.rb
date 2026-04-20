# frozen_string_literal: true

module DungeonMaster
  module WorldTurn
    class NpcActionResolutionLogPayload
      def initialize(npc_name:, action:, attack_modifier:, damage_dice:, player_hp_delta:, npc_mutations:, lines:)
        @npc_name = npc_name
        @action = action
        @attack_modifier = attack_modifier
        @damage_dice = damage_dice
        @player_hp_delta = player_hp_delta
        @npc_mutations = npc_mutations
        @lines = lines
      end

      def to_h
        {
          npc: @npc_name,
          action: @action,
          attack_modifier: @attack_modifier,
          damage_dice: @damage_dice,
          player_hp_delta: @player_hp_delta,
          npc_mutations: @npc_mutations,
          lines: @lines
        }
      end
    end
  end
end
