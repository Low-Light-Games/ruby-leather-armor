# frozen_string_literal: true

module DungeonMaster
  module Battlefield
    # On combat end: archive active row, set last_battlefield_ref, clear battlefield_ref.
    class ArchiveCombatEnd
      class << self
        def call(adventure:)
          ctx = adventure.combat_context
          return unless ctx.is_a?(Hash)

          normalized_combat_context = ctx.deep_stringify_keys
          return if normalized_combat_context["active"] == true

          battlefield_reference = BattlefieldReference.from_hash(normalized_combat_context["battlefield_ref"])
          active_row = adventure.adventure_battlefields.where(status: "active").first
          return if battlefield_reference.nil? && active_row.blank?

          battlefield = if battlefield_reference
                          adventure.adventure_battlefields.find_by(id: battlefield_reference.id) || active_row
               else
                 active_row
               end
          return if battlefield.blank?

          Adventure.transaction do
            battlefield&.reload
            if battlefield&.status == "active"
              battlefield.archive!
              battlefield.reload
            end

            archived_reference = BattlefieldReference.new(
              id: battlefield&.id || battlefield_reference&.id,
              version: battlefield&.version || battlefield_reference&.version,
              topology: battlefield&.topology || battlefield_reference&.topology || "square"
            )
            archived_context = CombatContextReferencePatch.clear(normalized_combat_context)
            last = archived_reference.to_h
            archived_context["last_battlefield_ref"] = last if last["id"].present?
            adventure.update!(combat_context: archived_context)
          end
          adventure.reload
        end
      end
    end
  end
end
