# frozen_string_literal: true

module DungeonMaster
  module Battlefield
    # On combat end: archive active row, set last_battlefield_ref, clear battlefield_ref.
    class ArchiveCombatEnd
      class << self
        def call(adventure:)
          ctx = adventure.combat_context
          return unless ctx.is_a?(Hash)

          s = ctx.deep_stringify_keys
          return if s["active"] == true

          ref = s["battlefield_ref"]
          active_row = adventure.adventure_battlefields.where(status: "active").first
          return if ref.blank? && active_row.blank?

          bf = if ref.present?
                 adventure.adventure_battlefields.find_by(id: ref["id"]) || active_row
               else
                 active_row
               end
          return if bf.blank?

          Adventure.transaction do
            bf&.reload
            if bf&.status == "active"
              bf.archive!
              bf.reload
            end
            last = {
              "id" => bf&.id || ref&.dig("id"),
              "version" => bf&.version || ref&.dig("version"),
              "topology" => bf&.topology || ref&.dig("topology") || "square"
            }.compact
            s["last_battlefield_ref"] = last if last["id"].present?
            s.delete("battlefield_ref")
            adventure.update!(combat_context: s)
          end
          adventure.reload
        end
      end
    end
  end
end
