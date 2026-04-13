# frozen_string_literal: true

module DungeonMaster
  module Battlefield
    # JSON-friendly snapshot for adventure API (active combat only).
    module ApiSnapshot
      module_function

      def for_adventure(adventure)
        EnsureForActiveCombat.call(adventure: adventure)
        adventure.reload

        ctx = adventure.combat_context
        return nil unless ctx.is_a?(Hash) && ctx["active"] == true

        ref = ctx["battlefield_ref"]
        return nil if ref.blank?

        bf = adventure.adventure_battlefields.find_by(id: ref["id"], status: "active")
        return nil unless bf

        {
          "id" => bf.id,
          "version" => bf.version,
          "topology" => bf.topology,
          "tokens" => bf.tokens,
          "viewport" => bf.viewport,
          "world" => bf.world
        }
      end
    end
  end
end
