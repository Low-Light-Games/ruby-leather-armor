# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step: Stagehand (output orchestration).
    #
    # Code-only step — no AI call. Sits between Verdict and Narrate/ContextUpdates.
    # Responsibilities:
    #   1. Package verdict outcome + dm_brief into a narrative seed for Narrate
    #   2. Package factual outcome + mutations into directives for ContextUpdate
    #   3. Orchestrate Narrate + ContextUpdate based on narration_mode config:
    #        "parallel"   — both run simultaneously (default)
    #        "subjugated" — context updates run first, then narrate sees fresh DB state
    module Stagehand
      private

      # Unified output phase for all pipeline flow paths.
      #
      # @param intent [Hash] the converged intent from Beacon
      # @param narrate_seed [String, nil] factual outcome or narrative seed for narrate
      # @param mutations [Hash, nil] verdict mutations (already applied to DB)
      # @param dm_brief [String, nil] plot guidance from chronicler
      # @param player_action [String, nil] raw player input (no-mechanics path)
      # @param extra [Hash] additional result keys to merge (e.g. encounter_interrupted)
      def run_output_phase(intent, narrate_seed:, mutations:, dm_brief: nil,
                           player_action: nil, extra: {})
        narration_mode = @config.get("narration_mode") || "parallel"

        what_happened = narrate_seed || player_action || intent[:intention]

        if narration_mode == "subjugated"
          run_subjugated_output(intent, narrate_seed: narrate_seed, what_happened: what_happened,
                                mutations: mutations, dm_brief: dm_brief, player_action: player_action)
        else
          run_parallel_output(intent, narrate_seed: narrate_seed, what_happened: what_happened,
                              mutations: mutations, dm_brief: dm_brief, player_action: player_action)
        end => narration

        { action: :narrated, narrative: narration[:narrative],
          adventure_complete: narration[:adventure_complete] }.merge(extra)
      end

      def run_parallel_output(intent, narrate_seed:, what_happened:, mutations:,
                              dm_brief:, player_action:)
        narration = nil

        narrate_thread = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            narration = run_narrate(narrate_seed, player_action: player_action,
                                    intent: intent, dm_brief: dm_brief)
          end
        end
        ctx_thread = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            run_context_updates(what_happened, mutations,
                                affected_contexts: intent[:affected_contexts],
                                macro_significant: intent[:macro_significant])
          end
        end

        narrate_thread.value
        ctx_thread.value
        narration
      end

      def run_subjugated_output(intent, narrate_seed:, what_happened:, mutations:,
                                dm_brief:, player_action:)
        run_context_updates(what_happened, mutations,
                            affected_contexts: intent[:affected_contexts],
                            macro_significant: intent[:macro_significant])

        run_narrate(narrate_seed, player_action: player_action,
                    intent: intent, dm_brief: dm_brief)
      end
    end
  end
end
