# frozen_string_literal: true

module PlayerTurn
  module Steps
    class LoremasterInputs
      attr_reader :what_happened, :mutations, :active_facts

      def initialize(what_happened:, mutations:, active_facts:)
        @what_happened = what_happened
        @mutations     = mutations
        @active_facts  = active_facts
        freeze
      end
    end
  end
end
