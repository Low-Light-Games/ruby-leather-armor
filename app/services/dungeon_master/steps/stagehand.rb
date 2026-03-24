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
    #        "parallel"   — both run simultaneously (default)
    #        "subjugated" — context updates run first, then narrate sees fresh DB state
    module Stagehand
      private

      def run_narrative_phase(intent, narrate_seed:, mutations:, dm_brief: nil, forbidden_elements: [], extra: {})
        warmaster_result = maybe_initialize_combat(intent)
        if warmaster_result && warmaster_result[:status] == :awaiting_initiative
          # ContextUpdate runs before the initiative prompt goes to the player so
          # contexts reflect combat beginning at pause time, not only after the roll.
          run_context_updates(narrate_seed, mutations)
          return {
            action: :awaiting_initiative,
            intent: intent,
            creature_data: warmaster_result[:creature_data],
            narrate_seed: narrate_seed,
            mutations: mutations
          }.merge(extra)
        end

        narration_mode = @config.get("narration_mode") || "parallel"
        enc_triggered = extra[:encounter_triggered] == true

        if narration_mode == "subjugated"
          run_subjugated_narrative(intent, narrate_seed: narrate_seed,
                                   mutations: mutations, dm_brief: dm_brief,
                                   forbidden_elements: forbidden_elements,
                                   encounter_triggered: enc_triggered)
        else
          run_parallel_narrative(intent, narrate_seed: narrate_seed,
                                 mutations: mutations, dm_brief: dm_brief,
                                 forbidden_elements: forbidden_elements,
                                 encounter_triggered: enc_triggered)
        end => narration

        adventure_complete = @loop&.get("adventure_complete") == true

        { action: :narrated, narrative: narration[:narrative],
          adventure_complete: adventure_complete }.merge(extra)
      end

      def run_parallel_narrative(intent, narrate_seed:, mutations:,
                                 dm_brief:, forbidden_elements: [], encounter_triggered: false)
        narration = nil

        narrate_thread = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            narration = run_narrate(narrate_seed, intent: intent, dm_brief: dm_brief,
                                    forbidden_elements: forbidden_elements,
                                    encounter_triggered: encounter_triggered)
          end
        end
        ctx_thread = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            run_context_updates(narrate_seed, mutations,
                                macro_significant: intent[:macro_significant])
          end
        end

        narrate_thread.value
        ctx_thread.value
        narration
      end

      def run_subjugated_narrative(intent, narrate_seed:, mutations:,
                                   dm_brief:, forbidden_elements: [], encounter_triggered: false)
        run_context_updates(narrate_seed, mutations,
                            macro_significant: intent[:macro_significant])

        run_narrate(narrate_seed, intent: intent, dm_brief: dm_brief,
                    forbidden_elements: forbidden_elements,
                    encounter_triggered: encounter_triggered)
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
