# frozen_string_literal: true

module PlayerTurn
  module PromptViews
    class SanityCheckerPromptContext
      attr_reader :condition_restrictions, :established_facts, :nearby_npcs, :nearby_locations,
                  :combat_active, :combat_turn_order

      def initialize(condition_restrictions: [],
                     established_facts: [], nearby_npcs: [], nearby_locations: [],
                     combat_active: false, combat_turn_order: [])
        @condition_restrictions = Array(condition_restrictions)
        @established_facts = Array(established_facts)
        @nearby_npcs = Array(nearby_npcs)
        @nearby_locations = Array(nearby_locations)
        @combat_active = combat_active
        @combat_turn_order = Array(combat_turn_order)
      end
    end
  end
end
