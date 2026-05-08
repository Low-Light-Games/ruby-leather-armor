# frozen_string_literal: true

module Battlefield
  class EnsureForActiveCombat
    class << self
      def call(adventure:, sheet: nil)
        sheet ||= AdventureSheet.for_adventure(adventure)
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
