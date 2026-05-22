# frozen_string_literal: true

module PlayerTurn
  module Steps
    module SocialMaster
      class Extraction
        attr_reader :npcs, :reasoning

        def initialize(npcs:, reasoning:)
          @npcs      = npcs
          @reasoning = reasoning
        end

        def self.empty
          new(npcs: [], reasoning: nil)
        end
      end
    end
  end
end
