# frozen_string_literal: true

module DungeonMaster
  module PromptViews
    class SanityCheckerPromptContext
      # `established_facts` replaced `micro_contexts` as the dynamic-state
      # input to the World Consistency Check when the facts store cutover
      # (plan: narrative facts store for world sanity, C10) landed. It is
      # an array of `{fact_id:, text:, kind:, polarity:, distance:}`
      # hashes, top-K-retrieved by cosine similarity against the player's
      # intent via `Lore::FactsLookup`. Micro-contexts remain the
      # structured mutation surface for ContextUpdate and other
      # consumers; they are simply no longer interrogated by
      # `sanity_checker_world`.
      attr_reader :condition_restrictions, :scene_summary, :scene_history,
                  :established_facts, :npc_names, :combat_active, :combat_turn_order

      def initialize(condition_restrictions: [], scene_summary: nil, scene_history: [],
                     established_facts: [], npc_names: [], combat_active: false,
                     combat_turn_order: [])
        @condition_restrictions = Array(condition_restrictions)
        @scene_summary = scene_summary
        @scene_history = Array(scene_history)
        @established_facts = Array(established_facts)
        @npc_names = Array(npc_names)
        @combat_active = combat_active
        @combat_turn_order = Array(combat_turn_order)
      end
    end
  end
end
