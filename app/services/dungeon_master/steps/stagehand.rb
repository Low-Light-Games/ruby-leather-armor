# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step: Stagehand (narrative phase orchestration).
    #
    # Code-only step — no AI call. Sits between Mechanic/Momentum and the
    # narrative/context-update phase.
    # Responsibilities:
    #   1. Check if combat signal from ParallelEvaluation warrants Warmaster (Path B)
    #   2. Run ContextUpdate before any awaiting_initiative early return (Path B)
    #   3. Orchestrate Narrate + ContextUpdate based on narration_mode config:
    #        "parallel"   — narrate + context updates sent to Node /fan_out together (default)
    #        "subjugated" — context updates via Node fan-out first, then narrate sequentially
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
        unless pipeline.combined_seed
          @log&.play_log!("pipeline_error", "Narrate step reached without an outcome — nothing to narrate",
                          parsed_response: { encounter_scene: @loop&.get("encounter_scene"),
                                             verdict_outcome: @loop&.get("verdict_outcome") }.compact)
          raise AiError, "Narrate step reached without an outcome — nothing to narrate"
        end

        broadcast_progress("Writing the story...")
        evaluator_url = ENV.fetch("EVALUATOR_URL", "http://evaluator:3001")

        narrate_prompt = build_narrate_prompt(pipeline)
        ctx_prompts    = build_context_update_prompts(pipeline.combined_seed, mutations,
                                                      macro_significant: intent[:macro_significant])

        results = call_evaluator!("#{evaluator_url}/fan_out",
                                  [narrate_prompt, *ctx_prompts],
                                  pipeline.combined_seed.to_s.truncate(120),
                                  phase: "parallel_narrative")

        narrate_raw    = results.find { |r| r.dig("meta", "step") == "narrate" }
        parsed_narrate = narrate_raw&.dig("parsed_response") || {}

        # Fallback: if the model returned raw prose instead of JSON the node
        # service leaves parsed_response nil and exposes raw_response.
        if !parsed_narrate["narrative"].present? && narrate_raw&.dig("raw_response").present?
          raw_text = narrate_raw["raw_response"].to_s.strip
          parsed_narrate = { "narrative" => raw_text } if raw_text.present?
        end

        raise AiError, "Narrate step returned no narrative — model produced: #{parsed_narrate.inspect.truncate(200)}" \
          unless parsed_narrate["narrative"].present?

        apply_context_update_results(results, macro_significant: intent[:macro_significant])

        { narrative: parsed_narrate["narrative"] }
      end

      def build_narrate_prompt(pipeline)
        system_prompt = PromptRenderer.render("narrate",
          loop:              @loop,
          pipeline:          pipeline,
          time_context:      @adventure.time_context || {},
          pacing_text:       PromptHelpers.pacing_instructions(@config),
          directed_play_text: PromptHelpers.directed_play_instructions(@adventure))

        {
          system_prompt: system_prompt,
          user_message:  pipeline.combined_seed,
          model:         @config.model_for("narrate"),
          max_tokens:    @config.token_budget_for("narrate"),
          meta:          { step: "narrate" }
        }
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
