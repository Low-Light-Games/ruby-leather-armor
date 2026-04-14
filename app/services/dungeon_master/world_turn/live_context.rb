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

      # Builds a canonical combat-context hash from component parts.
      # +overrides+ keys take precedence over values read from +ctx+.
      def build(ctx, participants, overrides = {})
        base = {
          "active"        => ctx["active"],
          "round"         => ctx["round"],
          "current_turn"  => ctx["current_turn"],
          "turn_order"    => ctx["turn_order"],
          "participants"  => participants,
          "terrain_notes" => ctx["terrain_notes"]
        }.merge(overrides)
        base["battlefield_ref"]      = ctx["battlefield_ref"]      if ctx["battlefield_ref"].present?
        base["last_battlefield_ref"] = ctx["last_battlefield_ref"] if ctx["last_battlefield_ref"].present?
        base
      end
    end
  end
end
