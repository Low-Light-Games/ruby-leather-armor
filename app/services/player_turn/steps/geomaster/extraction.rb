# frozen_string_literal: true

module PlayerTurn
  module Steps
    module Geomaster
      class Extraction
        attr_reader :locations, :reasoning

        def initialize(locations:, reasoning:)
          @locations = locations
          @reasoning = reasoning
        end

        def self.empty
          new(locations: [], reasoning: nil)
        end
      end
    end
  end
end
