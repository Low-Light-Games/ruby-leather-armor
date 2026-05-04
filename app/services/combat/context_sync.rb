# frozen_string_literal: true

module Combat
  # Re-renders combat_context.participants from canonical state
  # (creature_sheets + player sheet) so the JSONB shadow doesn't drift
  # away from the live data after a deterministic mutation.
  #
  # The free-text combat path already rebuilds participants via
  # WorldTurn::CombatAdvancement.build_after_world_turn at the end of
  # the round; the deterministic HUD path mutates creature_sheets
  # directly without touching the JSONB, so this is its sync seam.
  module ContextSync
    module_function

    def refresh_participants!(adventure, sheet)
      adventure.with_lock do
        ctx = adventure.combat_context.deep_dup.deep_stringify_keys
        next unless ctx["participants"].is_a?(Array)

        ctx["participants"] = ctx["participants"].map do |p|
          DungeonMaster::Utilities::Combatant.refresh_from_live_sources(p, adventure: adventure, sheet: sheet)
        end
        adventure.update!(combat_context: ctx)
      end
    rescue StandardError => e
      Rails.logger.warn("[Combat::ContextSync] refresh failed: #{e.message}")
    end
  end
end
