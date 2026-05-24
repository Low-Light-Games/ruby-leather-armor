# frozen_string_literal: true

module PlayerTurn
  module Steps
    module Stagehand
      private

      def run_narrative_phase(intent, narration_context:, mutations:, extra: {})
        warmaster_result = maybe_initialize_combat(intent)
        narrate_output = run_parallel_narrative(intent, narration_context: narration_context, mutations: mutations)

        if warmaster_result && warmaster_result[:status] == :awaiting_initiative
          opener_outcome = narrate_output.narrative.to_s.presence
          extras_with_opener = opener_outcome ? extra.merge(opener_outcome: opener_outcome) : extra
          return Narration::PhaseResults.awaiting_initiative(
            intent: intent,
            creature_data: warmaster_result[:creature_data],
            mutations: mutations,
            extras: extras_with_opener,
          ).to_h
        end

        Narration::PhaseResults.narrated(
          narrative: narrate_output.narrative,
          adventure_complete: @loop&.get("adventure_complete") == true,
          extras: extra,
        ).to_h
      end

      def run_parallel_narrative(intent, narration_context:, mutations:)
        seed = narration_context.combined_seed

        scene_facts   = retrieve_scene_facts_for_narrate(intent)
        outcome_facts = retrieve_outcome_facts_for_narrate(seed)

        include_ai_combat_context = combat_active?

        narrate_prompts = [
          narrate_evaluator_prompt(narration_context, scene_facts: scene_facts, outcome_facts: outcome_facts),
        ]
        narrate_prompts << combat_context_evaluator_prompt(seed, mutations) if include_ai_combat_context

        broadcast_progress("Writing the story...")
        narrate_by_step = evaluator_fan_out!(narrate_prompts, seed, phase: "narrative_phase")

        persist_narrative_phase_combat_context(narrate_by_step, mutations, ai_delta_included: include_ai_combat_context, phase: "narrative_phase")

        narrate_output = narrative_from_evaluator_result(evaluator_fan_out_result!(narrate_by_step, "narrate", "narrative_phase"))
        apply_narrate_mutations!(narrate_output.narrate_mutations)

        enqueue_masters_async(narrate_output.narrative.to_s)

        narrate_output
      end

      def enqueue_masters_async(narrative_text)
        GameMasterLoremasterJob.perform_later(
          @adventure.id,
          narrative_text,
          registry_entry_uuid: @log.registry_entry_uuid,
          adventure_loop_id:   @loop&.id,
          user_id:             @user&.id,
        )
      end

      def apply_narrate_mutations!(narrate_mutations)
        return if narrate_mutations.blank?

        apply_mutations(narrate_mutations)
        snapshot_contexts_to_loop if combat_active?

        @log&.play_log!(
          "narrate_mutations_applied",
          "Narrate-issued mutations applied",
          parsed_response: narrate_mutations,
        )
      rescue StandardError => e
        @log.report_error(e, context: {
          step: "narrate",
          adventure_id: @adventure&.id,
          loop_id: @loop&.id,
          source: "apply_narrate_mutations",
        })
        @log&.play_log!(
          "narrate_mutations_failed",
          "Narrate mutations failed: #{e.class}",
          parsed_response: { error: e.message.to_s.truncate(500) },
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

      def social_master_evaluator_prompt(inputs)
        Steps::SocialMaster.turn_evaluator_prompt(inputs: inputs, config: @config)
      end

      def geomaster_evaluator_prompt(inputs)
        Steps::Geomaster.turn_evaluator_prompt(inputs: inputs, config: @config)
      end

      def build_social_master_inputs(narrative_text)
        Steps::SocialMaster::Inputs.new(
          narrative:       narrative_text,
          known_npc_names: AdventureNpc.for_adventure(@adventure).pluck(:name),
        )
      end

      def build_geomaster_inputs(narrative_text)
        Steps::Geomaster::Inputs.new(
          narrative:            narrative_text,
          known_location_names: AdventureLocation.for_adventure(@adventure).pluck(:name),
        )
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

      def apply_social_master_from_fan_out!(by_step)
        result = by_step["social_master"]
        return if result.nil?

        social   = Steps::SocialMaster.parse_output(result["parsed_response"])
        filtered = Lore::RuntimeEntityFilter.filter_npcs(adventure: @adventure, raw_npcs: social.npcs)
        records  = Lore::RuntimeEntityCoercer.build_npc_records(filtered)
        return if records.empty?

        Lore::ApplyNpcs.call(
          adventure: @adventure, log: @log, ai: @ai,
          npc_records: records, source: "runtime",
        )
      rescue StandardError => e
        handle_runtime_entity_failure(e, entity_type: "npcs")
      end

      def apply_geomaster_from_fan_out!(by_step)
        result = by_step["geomaster"]
        return if result.nil?

        geo      = Steps::Geomaster.parse_output(result["parsed_response"])
        filtered = Lore::RuntimeEntityFilter.filter_locations(adventure: @adventure, raw_locations: geo.locations)
        records  = Lore::RuntimeEntityCoercer.build_location_records(filtered)
        return if records.empty?

        Lore::ApplyLocations.call(
          adventure: @adventure, log: @log, ai: @ai,
          location_records: records, source: "runtime",
        )
      rescue StandardError => e
        handle_runtime_entity_failure(e, entity_type: "locations")
      end

      def handle_runtime_entity_failure(exception, entity_type:)
        @log.report_error(exception, context: {
          step: "loremaster",
          adventure_id: @adventure&.id,
          loop_id: @loop&.id,
          source: "apply_#{entity_type}_runtime",
        })
        @log.play_log!(
          "loremaster_#{entity_type}_failure",
          "Loremaster apply #{entity_type} failed: #{exception.class}",
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

      def persist_narrative_phase_combat_context(by_step, mutations, ai_delta_included:, phase:)
        canonical = CombatContextUpdate::CombatMutationState.new(mutations).canonical_combat_context

        if !ai_delta_included && canonical.blank?
          snapshot_contexts_to_loop
          return
        end

        delta = if ai_delta_included
                  CombatContextUpdate::CombatContextChangeSet.from_parsed(evaluator_fan_out_result!(by_step, CombatContextUpdate::STEP_NAME, phase)["parsed_response"])
                else
                  CombatContextUpdate::CombatContextChangeSet.empty
                end
        persist_combat_context(delta, mutations)
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
