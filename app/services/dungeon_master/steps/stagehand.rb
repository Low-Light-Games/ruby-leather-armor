# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step: Stagehand (output orchestration).
    #
    # Code-only step — no AI call. Sits between Verdict and Narrate/ContextUpdates.
    # Responsibilities:
    #   1. Check if combat beacon signaled combat_started (Path B Warmaster gate)
    #   2. Package verdict outcome + dm_brief into a narrative seed for Narrate
    #   3. Package factual outcome + mutations into directives for ContextUpdate
    #   4. Orchestrate Narrate + ContextUpdate based on narration_mode config:
    #        "parallel"   — both run simultaneously (default)
    #        "subjugated" — context updates run first, then narrate sees fresh DB state
    module Stagehand
      private

      def run_output_phase(intent, narrate_seed:, mutations:, dm_brief: nil,
                           player_action: nil, extra: {})
        warmaster_result = maybe_initialize_combat(intent)
        if warmaster_result && warmaster_result[:status] == :awaiting_initiative
          return {
            action: :awaiting_initiative,
            intent: intent,
            creature_data: warmaster_result[:creature_data],
            narrate_seed: narrate_seed,
            mutations: mutations
          }.merge(extra)
        end

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

      def maybe_initialize_combat(intent)
        combat_beacon = intent.dig(:beacon_results, :combat) || intent.dig(:beacon_results, "combat")
        return nil unless combat_beacon.is_a?(Hash)

        transition = combat_beacon["transition"] || combat_beacon[:transition]
        return nil unless transition == "combat_started"
        return nil if stagehand_combat_active?

        combatants = Array(combat_beacon["combatants"] || combat_beacon[:combatants])
        return nil if combatants.empty?

        Utilities::Warmaster.initialize_from_names!(
          adventure: @adventure, combatant_names: combatants,
          sheet: @sheet, log: @log, config: @config, ai: @ai)
      end

      def stagehand_combat_active?
        ctx = @adventure.combat_context
        ctx.is_a?(Hash) && ctx["active"] == true && Array(ctx["participants"]).any?
      end
    end
  end
end
