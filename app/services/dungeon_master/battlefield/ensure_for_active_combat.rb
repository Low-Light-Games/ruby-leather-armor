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
            next unless active_combat_context?(combat_context)

            participants = combat_participants(combat_context)
            battlefield_reference = CombatContextReferencePatch.reference_from(combat_context)
            reference_id = battlefield_reference&.id

            archive_non_matching_active_battlefields!(adventure, participants)
            collapse_duplicate_active_battlefields!(adventure, reference_id)

            next if referenced_active_battlefield_matches?(adventure, reference_id, participants)

            keeper = find_matching_active_battlefield(adventure, participants)
            if keeper
              adventure.update!(
                combat_context: CombatContextReferencePatch.attach(combat_context, battlefield: keeper)
              )
              next
            end

            recreate_battlefield_from_combat_context!(adventure, combat_context, sheet)
          end
        end

        private

        def active_combat_context?(combat_context)
          combat_context.is_a?(Hash) &&
            combat_context["active"] == true &&
            combat_participants(combat_context).any?
        end

        def combat_participants(combat_context)
          Array(combat_context["participants"])
        end

        def battlefield_matches_participants?(battlefield, participants)
          PersistCombatStart.same_token_set_as_participants?(battlefield.tokens, participants)
        end

        def archive_non_matching_active_battlefields!(adventure, participants)
          AdventureBattlefield.active_for(adventure.id).order(:id).find_each do |battlefield|
            next if battlefield_matches_participants?(battlefield, participants)

            battlefield.archive!
          end
        end

        def collapse_duplicate_active_battlefields!(adventure, reference_id)
          active_battlefields = AdventureBattlefield.active_for(adventure.id).order(:id).to_a
          return unless active_battlefields.many?

          keeper = preferred_active_battlefield(active_battlefields, reference_id)
          (active_battlefields - [keeper]).each(&:archive!)
        end

        def preferred_active_battlefield(active_battlefields, reference_id)
          referenced = active_battlefields.find { |battlefield| battlefield.id == reference_id } if reference_id&.positive?
          referenced || active_battlefields.first
        end

        def referenced_active_battlefield_matches?(adventure, reference_id, participants)
          return false unless reference_id&.positive?

          referenced_battlefield = adventure.adventure_battlefields.find_by(id: reference_id)
          referenced_battlefield&.status == "active" &&
            battlefield_matches_participants?(referenced_battlefield, participants)
        end

        def find_matching_active_battlefield(adventure, participants)
          AdventureBattlefield.active_for(adventure.id).order(:id).find do |battlefield|
            battlefield_matches_participants?(battlefield, participants)
          end
        end

        def recreate_battlefield_from_combat_context!(adventure, combat_context, sheet)
          combat_payload = CombatContextReferencePatch.clear(combat_context)
          PersistCombatStart.call(adventure: adventure, combat_data: combat_payload, sheet: sheet)
        end
      end
    end
  end
end
