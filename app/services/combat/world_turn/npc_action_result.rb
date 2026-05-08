# frozen_string_literal: true

module Combat
  module WorldTurn
    class NpcActionResult
      attr_reader :lines, :npc_mutations, :player_hp_delta, :battlefield_patches

      def initialize(lines:, npc_mutations:, player_hp_delta:, battlefield_patches:)
        @lines = lines
        @npc_mutations = npc_mutations
        @player_hp_delta = player_hp_delta.to_i
        @battlefield_patches = battlefield_patches
      end

      def to_h
        {
          lines: lines,
          npc_muts: npc_mutations,
          player_hp_delta: player_hp_delta,
          battlefield_patches: battlefield_patches
        }
      end
    end
  end
end
