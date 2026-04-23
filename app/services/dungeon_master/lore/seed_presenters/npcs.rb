# frozen_string_literal: true

module DungeonMaster
  module Lore
    module SeedPresenters
      class Npcs
        def self.call(adventure:)
          new(adventure: adventure).call
        end

        def initialize(adventure:)
          @adventure = adventure
        end

        def call
          rows = StoryNpc.for_adventure(@adventure).ordered_by_id.map { |npc| format_row(npc) }
          rows.any? ? rows.join("\n") : "(none)"
        end

        private

        def format_row(npc)
          parts = ["- #{npc.name} (role: #{npc.role}, attitude: #{npc.attitude})"]
          parts << "  description: #{npc.description}" if npc.description.present?
          parts.join("\n")
        end
      end
    end
  end
end
