# frozen_string_literal: true

module DungeonMaster
  module WorldTurn
    # In-memory combat_context with participant hp/conditions from live sheets
    # (persisted combat_context lags until ContextUpdate).
    module LiveContext
      module_function

      # @param base_ctx [Hash] snapshot of adventure.combat_context at world-turn start
      def merge_live_participants(base_ctx, adventure:, sheet:)
        ctx = base_ctx.deep_dup.deep_stringify_keys
        ctx["participants"] = Array(ctx["participants"]).map do |p|
          Utilities::Combatant.refresh_from_live_sources(p, adventure: adventure, sheet: sheet)
        end
        ctx
      end

    end
  end
end
