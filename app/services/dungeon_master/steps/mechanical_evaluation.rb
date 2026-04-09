# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Merges per-domain evaluation results from UnifiedEvaluation into a single
    # flat structure for downstream resolution (finish_resolution, auto-success filter, etc.).
    module MechanicalEvaluation
      private

      def merge_mechanical_evaluations(evaluations)
        {
          player_rolls: evaluations.flat_map { |e| e[:player_rolls] },
          npc_actions: evaluations.flat_map { |e| e[:npc_actions] },
          consequences: evaluations.flat_map { |e| e[:consequences] },
          mechanical_summaries: evaluations.map { |e| "[#{e[:domain].upcase}] #{e[:mechanical_summary]}" }
        }
      end

      # Merge domains, dedupe rolls, log mech_eval line, strip auto-successes (AdventureLoopResolution#resolve).
      def merge_mechanical_evaluations_and_prepare_rolls(evaluations)
        merged = merge_mechanical_evaluations(evaluations)
        Rolls::PlayerRolls.deduplicate_rolls!(merged, log: @log)
        rolls_desc = merged[:player_rolls].map { |r| "#{r[:skill] || r[:type]} DC #{r[:dc]} (#{r[:domain]})" }.join(", ")
        @loop&.log_step("mech_eval", rolls_desc.presence || "No rolls")
        Rolls::PlayerRolls.filter_auto_success_rolls!(merged, log: @log, sheet: @sheet)
        merged
      end
    end
  end
end
