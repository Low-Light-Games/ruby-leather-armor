# frozen_string_literal: true

module DungeonMaster
  module Battlefield
    # Text slice for LLM prompts (Combat GM, NPC action, DM query).
    module PromptSerializer
      module_function

      def slice_for_adventure(adventure)
        ctx = adventure.combat_context
        return nil unless ctx.is_a?(Hash)

        s = ctx.deep_stringify_keys
        ref = s["battlefield_ref"].presence || s["last_battlefield_ref"]
        return nil if ref.blank?

        bf = adventure.adventure_battlefields.find_by(id: ref["id"])
        return "Battlefield id=#{ref['id']} (row missing) version=#{ref['version']}" unless bf

        lines = []
        lines << "Battlefield row id=#{bf.id} status=#{bf.status} version=#{bf.version} topology=#{bf.topology}"
        lines << "Viewport: #{bf.viewport.to_json}"
        lines << "Tokens: #{bf.tokens.to_json}"
        world = bf.world.is_a?(Hash) ? bf.world : {}
        cell_count = world["cells"].is_a?(Hash) ? world["cells"].size : 0
        lines << "Terrain cells defined: #{cell_count}"
        lines.join("\n")
      end
    end
  end
end
