# frozen_string_literal: true

module DungeonMaster
  module Lore
    module SeedPresenters
      class Clues
        def self.call(adventure:)
          new(adventure: adventure).call
        end

        def initialize(adventure:)
          @adventure = adventure
        end

        def call
          rows = StoryClue.for_adventure(@adventure).ordered_by_id.map { |clue| format_row(clue) }
          rows.any? ? rows.join("\n") : "(none)"
        end

        private

        def format_row(clue)
          parts = ["- #{clue.title} (discovery: #{clue.discovery_method}, difficulty: #{clue.difficulty})"]
          parts << "  description: #{clue.description}" if clue.description.present?
          parts.join("\n")
        end
      end
    end
  end
end
