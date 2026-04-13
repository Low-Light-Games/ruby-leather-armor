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
          c = Utilities::Combatant.from_context_hash(p)
          if c.player? && sheet
            Utilities::Combatant.from_player_sheet(sheet, initiative: c.initiative).to_context_hash
          elsif c.creature_sheet_id.present?
            cs = adventure.creature_sheets.find_by(id: c.creature_sheet_id)
            cs ? Utilities::Combatant.from_creature_sheet(cs, initiative: c.initiative).to_context_hash : c.to_context_hash
          else
            c.to_context_hash
          end
        end
        ctx
      end
    end
  end
end
