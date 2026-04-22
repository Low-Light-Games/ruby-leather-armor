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

      def run_narrative_phase(intent, narration_context:, mutations:, extra: {})
        warmaster_result = maybe_initialize_combat(intent)
        if warmaster_result && warmaster_result[:status] == :awaiting_initiative
          # ContextUpdate runs before the initiative prompt goes to the player so
          # contexts reflect combat beginning at pause time, not only after the roll.
          run_context_updates(narration_context.combined_seed, mutations)
          return {
            action: :awaiting_initiative,
            intent: intent,
            creature_data: warmaster_result[:creature_data],
            mutations: mutations
          }.merge(extra)
        end

        # v1 latency: combat rounds are never macro-significant; skip macro context LLM cost.
        intent = intent.merge(macro_significant: false) if stagehand_combat_active?

        narration_mode = @config.get("narration_mode") || "parallel"

        if narration_mode == "subjugated"
          run_subjugated_narrative(intent, narration_context: narration_context, mutations: mutations)
        else
          run_parallel_narrative(intent, narration_context: narration_context, mutations: mutations)
        end => narration

        adventure_complete = @loop&.get("adventure_complete") == true

        { action: :narrated, narrative: narration[:narrative],
          adventure_complete: adventure_complete }.merge(extra)
      end

      def run_parallel_narrative(intent, narration_context:, mutations:)
        seed = narration_context.combined_seed

        broadcast_progress("Writing the story...")
        broadcast_progress("Remembering the world...")

        # Snapshot before the fan-out dispatches — inputs must capture
        # post-mutation state (docs/pipeline_steps.md Decision 37).
        loremaster_inputs = build_loremaster_inputs(seed, mutations)

        prompts = [narrate_evaluator_prompt(narration_context)]
        prompts.concat(build_micro_context_updater_prompts(seed, mutations, allow_combat_initialization: true))
        prompts << macro_context_evaluator_prompt(seed) if intent[:macro_significant]
        prompts << loremaster_evaluator_prompt(loremaster_inputs)

        # All prompts are built on the main thread before this single HTTP call; Node runs
        # LLM calls concurrently but returns results in request order — see evaluator index.js.
        by_step = evaluator_fan_out!(prompts, seed, phase: "narrative_phase")

        micro_parsed = aggregate_micro_context_results(by_step)
        macro_parsed = if intent[:macro_significant]
                         evaluator_fan_out_result!(by_step, "macro_narrative_update", "narrative_phase")["parsed_response"] || {}
                       else
                         {}
                       end

        apply_context_update_results(micro_parsed, macro_parsed,
          macro_significant: intent[:macro_significant],
          mutations: mutations)

        apply_loremaster_from_fan_out!(by_step)

        narrative_from_evaluator_result(evaluator_fan_out_result!(by_step, "narrate", "narrative_phase"))
      end

      def run_subjugated_narrative(intent, narration_context:, mutations:)
        run_context_updates(narration_context.combined_seed, mutations,
                            macro_significant: intent[:macro_significant])

        result = run_narrate(narration_context)

        run_loremaster_subjugated(narration_context.combined_seed, mutations)

        result
      end

      def build_loremaster_inputs(what_happened, mutations)
        Steps::LoremasterInputs.new(
          what_happened: what_happened.to_s,
          mutations: (mutations || {}).deep_stringify_keys,
          contexts_text: PromptHelpers.build_micro_contexts_block(@adventure).to_s,
          active_facts: active_facts_window,
        )
      end

      def loremaster_evaluator_prompt(inputs)
        Steps::Loremaster.turn_evaluator_prompt(inputs: inputs, config: @config)
      end

      def apply_loremaster_from_fan_out!(by_step)
        result = by_step["loremaster"]
        return if result.nil?

        parsed = result["parsed_response"]
        Lore::ApplyResults.call(
          adventure: @adventure,
          loop: @loop,
          log: @log,
          ai: @ai,
          result: parsed || {},
        )
      rescue StandardError => e
        handle_loremaster_failure(e, source: "apply_results")
      end

      def run_loremaster_subjugated(what_happened, mutations)
        inputs = build_loremaster_inputs(what_happened, mutations)
        payload = loremaster_evaluator_prompt(inputs)

        prompt_summary = "Loremaster (subjugated)"
        request_body = { system_prompt: payload[:system_prompt], user_message: payload[:user_message] }
        parsed = timed_ai_call("loremaster", prompt_summary, request_body) do
          raw = @ai.chat(
            system_prompt: payload[:system_prompt],
            user_message:  payload[:user_message],
            max_tokens:    payload[:max_tokens],
            step_name:     "loremaster",
            model:         payload[:model],
          )
          [raw, @ai.parse_json(raw)]
        end

        Lore::ApplyResults.call(
          adventure: @adventure, loop: @loop, log: @log, ai: @ai,
          result: parsed || {},
        )
      rescue StandardError => e
        handle_loremaster_failure(e, source: "subjugated_call")
      end

      def handle_loremaster_failure(exception, source:)
        @log.report_error(exception, context: {
          step: "loremaster",
          adventure_id: @adventure&.id,
          loop_id: @loop&.id,
          source: source,
        })
        @log.play_log!(
          "loremaster_failure",
          "Loremaster #{source} failed: #{exception.class}",
          parsed_response: { error: exception.message.to_s.truncate(500) },
        )
      end

      def active_facts_window
        limit = (DmConfig.instance.narrative_facts_active_window.presence || 20).to_i
        limit = 20 if limit <= 0

        AdventureNarrativeFact
          .active
          .where(adventure_id: @adventure.id)
          .order(created_at: :desc, id: :desc)
          .limit(limit)
          .pluck(:id, :kind, :text)
          .map { |id, kind, text| { fact_id: id, kind: kind, text: text } }
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
          names_preparation_request: Utilities::Warmaster::NamesPreparationRequest.new(
            adventure: @adventure,
            combatant_names: combatants,
            sheet: @sheet,
            log: @log,
            config: @config,
            ai: @ai
          )
        )
      end

      def combat_transition?(transition)
        return false if transition.blank?

        DungeonMaster::CombatTransitions.start?(transition)
      end

      def stagehand_combat_active?
        ctx = @adventure.combat_context
        ctx.is_a?(Hash) && ctx["active"] == true && Array(ctx["participants"]).any?
      end
    end
  end
end
