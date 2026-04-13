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
            ref_id = ref["id"].to_i if ref.is_a?(Hash) && ref["id"].present?

            actives = adventure.adventure_battlefields.where(status: "active").order(:id).to_a
            if actives.many?
              keeper = actives.find { |b| b.id == ref_id } if ref_id&.positive?
              keeper ||= actives.first
              (actives - [keeper]).each(&:archive!)
              adventure.reload
            end

            if ref_id&.positive?
              bf = adventure.adventure_battlefields.find_by(id: ref_id)
              next if bf&.status == "active"
            end

            keeper = adventure.adventure_battlefields.where(status: "active").order(:id).first

            if keeper
              ctx2 = ctx.deep_dup.deep_stringify_keys
              ctx2["battlefield_ref"] = {
                "id" => keeper.id,
                "version" => keeper.version,
                "topology" => keeper.topology
              }
              adventure.update!(combat_context: ctx2)
              next
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
