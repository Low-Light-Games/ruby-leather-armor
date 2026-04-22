# frozen_string_literal: true

module DungeonMaster
  module Steps
    class LoremasterInputs
      attr_reader :what_happened, :mutations, :contexts_text, :active_facts

      def initialize(what_happened:, mutations:, contexts_text:, active_facts:)
        @what_happened = what_happened
        @mutations     = mutations
        @contexts_text = contexts_text
        @active_facts  = active_facts
        freeze
      end
    end
  end
end
