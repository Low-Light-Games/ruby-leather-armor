# frozen_string_literal: true

module DungeonMaster
  module Battlefield
    # Just-in-time battlefield row for adventures that enter combat without going through
    # initiative (e.g. stories starting mid-fight, admin-seeded combat_context, or legacy saves).
    # Idempotent: no-op when an active row already matches battlefield_ref.
    class EnsureForActiveCombat
      class << self
        def call(adventure:, sheet: nil)
          sheet ||= CharacterBlock.load_sheet(adventure)
          return unless sheet

          adventure.with_lock do
            adventure.reload
            ctx = adventure.combat_context
            next unless ctx.is_a?(Hash) && ctx["active"] == true
            next unless Array(ctx["participants"]).any?

            ref = ctx["battlefield_ref"]
            if ref.is_a?(Hash) && ref["id"].present?
              bf = adventure.adventure_battlefields.find_by(id: ref["id"])
              next if bf&.status == "active"
            end

            data = ctx.deep_dup.deep_stringify_keys
            data.delete("battlefield_ref")
            PersistCombatStart.call(adventure: adventure, combat_data: data, sheet: sheet)
          end
        end
      end
    end
  end
end
