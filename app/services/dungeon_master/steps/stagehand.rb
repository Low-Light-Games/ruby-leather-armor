# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step: Stagehand (narrative phase orchestration).
    #
    # Code-only step — no AI call. Sits between Mechanic/Momentum and Narrate/ContextUpdates.
    # Responsibilities:
    #   1. Check if combat signal from UnifiedEvaluation warrants Warmaster (Path B)
    #   2. Run ContextUpdate before any awaiting_initiative early return (Path B)
    #   3. Orchestrate Narrate + ContextUpdate based on narration_mode config:
    #        "parallel"   — both via Node POST /fan_out (default)
    #        "subjugated" — context updates run first, then narrate sees fresh DB state
    module Stagehand
      private

      def run_narrative_phase(intent, pipeline:, mutations:, extra: {})
        warmaster_result = maybe_initialize_combat(intent)
        if warmaster_result && warmaster_result[:status] == :awaiting_initiative
          # ContextUpdate runs before the initiative prompt goes to the player so
          # contexts reflect combat beginning at pause time, not only after the roll.
          run_context_updates(pipeline.combined_seed, mutations)
          return {
            action: :awaiting_initiative,
            intent: intent,
            creature_data: warmaster_result[:creature_data],
            mutations: mutations
          }.merge(extra)
        end

        narration_mode = @config.get("narration_mode") || "parallel"

        if narration_mode == "subjugated"
          run_subjugated_narrative(intent, pipeline: pipeline, mutations: mutations)
        else
          run_parallel_narrative(intent, pipeline: pipeline, mutations: mutations)
        end => narration

        adventure_complete = @loop&.get("adventure_complete") == true

        { action: :narrated, narrative: narration[:narrative],
          adventure_complete: adventure_complete }.merge(extra)
      end

      def run_parallel_narrative(intent, pipeline:, mutations:)
        seed = pipeline.combined_seed
        evaluator_url = ENV.fetch("EVALUATOR_URL", "http://evaluator:3001")

        broadcast_progress("Writing the story...")
        broadcast_progress("Remembering the world...")

        prompts = [narrate_evaluator_prompt(pipeline), micro_context_evaluator_prompt(seed, mutations)]
        prompts << macro_context_evaluator_prompt(seed) if intent[:macro_significant]

        results = call_evaluator!("#{evaluator_url}/fan_out", prompts, seed, phase: "narrative_phase")

        by_step = results.each_with_object({}) { |r, h| h[r.dig("meta", "step")] = r }

        micro_parsed = (by_step["micro_context_update"] || {})["parsed_response"] || {}
        macro_parsed = if intent[:macro_significant]
                         (by_step["macro_narrative_update"] || {})["parsed_response"] || {}
                       else
                         {}
                       end

        apply_context_update_results(micro_parsed, macro_parsed, macro_significant: intent[:macro_significant])

        narrative_from_evaluator_result(by_step["narrate"])
      end

      def run_subjugated_narrative(intent, pipeline:, mutations:)
        run_context_updates(pipeline.combined_seed, mutations,
                            macro_significant: intent[:macro_significant])

        run_narrate(pipeline)
      end

      def maybe_initialize_combat(intent)
        return nil if stagehand_combat_active?

        domain_results = intent[:domain_results]
        return nil unless domain_results.is_a?(Hash)

        combatants = []
        domain_results.each_value do |beacon|
          next unless beacon.is_a?(Hash)

          transition = beacon[:transition] || beacon["transition"]
          next unless combat_transition?(transition)

          combatants.concat(Array(beacon[:combatants] || beacon["combatants"]))
        end

        combatants = combatants.map(&:to_s).reject(&:blank?).uniq
        return nil if combatants.empty?

        Utilities::Warmaster.initialize_from_names!(
          adventure: @adventure, combatant_names: combatants,
          sheet: @sheet, log: @log, config: @config, ai: @ai)
      end

      def combat_transition?(transition)
        return false if transition.blank?

        transition == "combat_started" || transition.to_s.end_with?("_to_combat")
      end

      def stagehand_combat_active?
        ctx = @adventure.combat_context
        ctx.is_a?(Hash) && ctx["active"] == true && Array(ctx["participants"]).any?
      end
    end
  end
end
