# frozen_string_literal: true

module DungeonMaster
  module PromptViews
    class SanityCheckerPromptContext
      attr_reader :condition_restrictions, :scene_summary, :scene_history,
                  :established_facts, :nearby_npcs, :nearby_locations,
                  :combat_active, :combat_turn_order

      def initialize(condition_restrictions: [], scene_summary: nil, scene_history: [],
                     established_facts: [], nearby_npcs: [], nearby_locations: [],
                     combat_active: false, combat_turn_order: [])
        @condition_restrictions = Array(condition_restrictions)
        @scene_summary = scene_summary
        @scene_history = Array(scene_history)
        @established_facts = Array(established_facts)
        @nearby_npcs = Array(nearby_npcs)
        @nearby_locations = Array(nearby_locations)
        @combat_active = combat_active
        @combat_turn_order = Array(combat_turn_order)
      end
    end
  end
end
