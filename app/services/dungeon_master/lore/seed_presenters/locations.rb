# frozen_string_literal: true

module DungeonMaster
  module Lore
    module SeedPresenters
      class Locations
        def self.call(adventure:)
          new(adventure: adventure).call
        end

        def initialize(adventure:)
          @adventure = adventure
        end

        def call
          rows = (@adventure.story&.story_locations&.order(:id)&.to_a || []).map { |loc| format_row(loc) }
          rows.any? ? rows.join("\n") : "(none)"
        end

        private

        def format_row(location)
          parts = ["- #{location.name}"]
          parts << "  description: #{location.description}" if location.description.present?
          parts.join("\n")
        end
      end
    end
  end
end
