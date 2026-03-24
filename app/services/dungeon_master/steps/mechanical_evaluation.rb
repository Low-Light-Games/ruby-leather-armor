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
    end
  end
end
