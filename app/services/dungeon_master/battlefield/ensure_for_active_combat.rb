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
            combat_context = adventure.combat_context
            next unless combat_context.is_a?(Hash) && combat_context["active"] == true
            next unless Array(combat_context["participants"]).any?

            battlefield_reference = combat_context["battlefield_ref"]
            reference_id = battlefield_reference["id"].to_i if battlefield_reference.is_a?(Hash) && battlefield_reference["id"].present?
            participants = Array(combat_context["participants"])
            token_match = ->(bf) { PersistCombatStart.same_token_set_as_participants?(bf.tokens, participants) }

            actives = AdventureBattlefield.active_for(adventure.id).order(:id).to_a
            actives.each do |bf|
              bf.archive! unless token_match.call(bf)
            end
            adventure.reload

            actives = AdventureBattlefield.active_for(adventure.id).order(:id).to_a
            if actives.many?
              keeper = actives.find { |battlefield| battlefield.id == reference_id } if reference_id&.positive?
              keeper ||= actives.first
              (actives - [keeper]).each(&:archive!)
              adventure.reload
            end

            if reference_id&.positive?
              referenced_battlefield = adventure.adventure_battlefields.find_by(id: reference_id)
              next if referenced_battlefield&.status == "active" && token_match.call(referenced_battlefield)
            end

            keeper = AdventureBattlefield.active_for(adventure.id).order(:id).first

            if keeper && token_match.call(keeper)
              updated_combat_context = combat_context.deep_dup.deep_stringify_keys
              updated_combat_context["battlefield_ref"] = {
                "id" => keeper.id,
                "version" => keeper.version,
                "topology" => keeper.topology
              }
              adventure.update!(combat_context: updated_combat_context)
              next
            end

            combat_payload = combat_context.deep_dup.deep_stringify_keys
            combat_payload.delete("battlefield_ref")
            PersistCombatStart.call(adventure: adventure, combat_data: combat_payload, sheet: sheet)
          end
        end
      end
    end
  end
end
