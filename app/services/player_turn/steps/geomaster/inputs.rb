# frozen_string_literal: true

module PlayerTurn
  module Steps
    module Geomaster
      class Inputs
        attr_reader :narrative, :known_location_names

        def initialize(narrative:, known_location_names: [])
          @narrative            = narrative
          @known_location_names = known_location_names
          freeze
        end
      end
    end
  end
end
