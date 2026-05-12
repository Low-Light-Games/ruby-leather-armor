# frozen_string_literal: true

module PlayerTurn
  module Steps
    module Stagehand
      private

      def run_narrative_phase(intent, narration_context:, mutations:, extra: {})
        warmaster_result = maybe_initialize_combat(intent)
        narration = run_parallel_narrative(intent, narration_context: narration_context, mutations: mutations)

        if warmaster_result && warmaster_result[:status] == :awaiting_initiative
          opener_outcome = narration[:narrative].to_s.presence
          extras_with_opener = opener_outcome ? extra.merge(opener_outcome: opener_outcome) : extra
          return Narration::PhaseResults.awaiting_initiative(
            intent: intent,
            creature_data: warmaster_result[:creature_data],
            mutations: mutations,
            extras: extras_with_opener,
          ).to_h
        end

        Narration::PhaseResults.narrated(
          narrative: narration[:narrative],
          adventure_complete: @loop&.get("adventure_complete") == true,
          extras: extra,
        ).to_h
      end

      def run_parallel_narrative(intent, narration_context:, mutations:)
        seed = narration_context.combined_seed

        loremaster_inputs = build_loremaster_inputs(seed, mutations)

        scene_facts   = retrieve_scene_facts_for_narrate(intent)
        outcome_facts = retrieve_outcome_facts_for_narrate(seed)

        combat_context_required = combat_context_update_required?(mutations)

        prompts = [
          narrate_evaluator_prompt(narration_context, scene_facts: scene_facts, outcome_facts: outcome_facts),
          loremaster_evaluator_prompt(loremaster_inputs),
        ]
        if combat_context_required
          prompts << combat_context_evaluator_prompt(seed, mutations)
        end

        broadcast_progress("Writing the story...")
        by_step = evaluator_fan_out!(prompts, seed, phase: "narrative_phase")

        update_or_snapshot_combat_context(by_step, mutations, required: combat_context_required, phase: "narrative_phase")

        broadcast_progress("Remembering the world...")
        apply_loremaster_from_fan_out!(by_step)

        narrative_from_evaluator_result(evaluator_fan_out_result!(by_step, "narrate", "narrative_phase"))
      end

      def build_loremaster_inputs(what_happened, mutations)
        Steps::LoremasterInputs.new(
          what_happened: what_happened.to_s,
          mutations: (mutations || {}).deep_stringify_keys,
          active_facts: active_facts_window,
        )
      end

      def retrieve_scene_facts_for_narrate(intent)
        SceneFacts::ForResolution.call(
          adventure:   @adventure,
          intent_text: intent[:intention].to_s,
          ai:          @ai,
          log:         @log,
        )
      end

      def retrieve_outcome_facts_for_narrate(seed)
        SceneFacts::ForOutcome.call(
          adventure:     @adventure,
          what_happened: seed.to_s,
          ai:            @ai,
          log:           @log,
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
        handle_loremaster_failure(e)
      end

      def handle_loremaster_failure(exception)
        @log.report_error(exception, context: {
          step: "loremaster",
          adventure_id: @adventure&.id,
          loop_id: @loop&.id,
          source: "apply_results",
        })
        @log.play_log!(
          "loremaster_failure",
          "Loremaster apply_results failed: #{exception.class}",
          parsed_response: { error: exception.message.to_s.truncate(500) },
        )
      end

      def active_facts_window
        limit = (DmConfig.instance.narrative_facts_active_window.presence || 20).to_i
        limit = 20 if limit <= 0

        AdventureNarrativeFact
          .active_window_for(@adventure, limit: limit)
          .pluck(:id, :kind, :text)
          .map { |id, kind, text| { fact_id: id, kind: kind, text: text } }
      end

      def maybe_initialize_combat(intent)
        return nil if stagehand_combat_active?

        transition = intent[:transition] || intent["transition"]
        return nil unless combat_transition?(transition)

        roster = @current_cast_roster || PlayerTurn::CastRoster.empty
        return nil if roster.empty?

        result = Encounters::Warmaster.persist_combat_from_cast_roster!(
          adventure:                @adventure,
          cast_roster:              roster,
          target_actor_sheet_id: intent[:target_actor_sheet_id] || intent["target_actor_sheet_id"],
        )
        return nil if result[:status] == :no_creatures

        result
      end

      def update_or_snapshot_combat_context(by_step, mutations, required:, phase:)
        if required
          persist_combat_context(combat_context_delta(by_step, phase: phase), mutations)
        else
          snapshot_contexts_to_loop
        end
      end

      def combat_transition?(transition)
        return false if transition.blank?

        Combat::Transitions.start?(transition)
      end

      def stagehand_combat_active?
        state = Adventures::CombatState.from_adventure(@adventure)
        state.active? && state.has_participants?
      end
    end
  end
end
