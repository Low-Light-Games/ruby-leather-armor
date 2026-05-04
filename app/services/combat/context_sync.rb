# frozen_string_literal: true

module Combat
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
