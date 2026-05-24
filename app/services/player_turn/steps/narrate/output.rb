# frozen_string_literal: true

module PlayerTurn
  module Steps
    module Narrate
      class Output
        attr_reader :narrative, :narrate_mutations

        def initialize(narrative:, narrate_mutations: {})
          @narrative = narrative
          @narrate_mutations = narrate_mutations
          freeze
        end
      end
    end
  end
end
