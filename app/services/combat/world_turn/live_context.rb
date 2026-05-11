# frozen_string_literal: true

module Combat
  module WorldTurn
    module LiveContext
      module_function

      # @param base_ctx [Hash] snapshot of adventure.combat_context at world-turn start
      def merge_live_participants(base_ctx, adventure:, sheet:)
        ctx = base_ctx.deep_dup.deep_stringify_keys
        ctx["participants"] = Array(ctx["participants"]).map do |p|
          Combat::Combatant.refresh_from_live_sources(p, adventure: adventure, sheet: sheet)
        end
        ctx
      end

    end
  end
end
