# frozen_string_literal: true

module DungeonMaster
  module Battlefield
    # Bootstrap / repair helper: ensures exactly one active battlefield row whose token set
    # matches the current combat participants, and that combat_context.battlefield_ref points to it.
    #
    # Used by DM query, roll-pause metadata, and prompt serialisation — i.e., any path that reads
    # battlefield state without going through PersistCombatStart (initiative flow).
    #
    # Resolution order (all inside with_lock):
    #   1. Archive active rows whose token set doesn't match current participants.
    #   2. If multiple matching active rows remain, keep the one battlefield_ref points at
    #      (or the oldest) and archive the rest.
    #   3. If battlefield_ref already points at the surviving active+matching row → no-op.
    #   4. If a surviving matching row exists but battlefield_ref is stale/missing → reattach ref.
    #   5. If no matching active row survives → call PersistCombatStart to create a fresh one.
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
            participants = Array(ctx["participants"])
            token_match = ->(bf) { PersistCombatStart.same_token_set_as_participants?(bf.tokens, participants) }

            actives = adventure.adventure_battlefields.where(status: "active").order(:id).to_a
            actives.each do |bf|
              bf.archive! unless token_match.call(bf)
            end
            adventure.reload

            actives = adventure.adventure_battlefields.where(status: "active").order(:id).to_a
            if actives.many?
              keeper = actives.find { |b| b.id == ref_id } if ref_id&.positive?
              keeper ||= actives.first
              (actives - [keeper]).each(&:archive!)
              adventure.reload
            end

            if ref_id&.positive?
              bf = adventure.adventure_battlefields.find_by(id: ref_id)
              next if bf&.status == "active" && token_match.call(bf)
            end

            keeper = adventure.adventure_battlefields.where(status: "active").order(:id).first

            if keeper && token_match.call(keeper)
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
