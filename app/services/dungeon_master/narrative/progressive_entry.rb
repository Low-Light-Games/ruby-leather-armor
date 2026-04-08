# frozen_string_literal: true

module DungeonMaster
  module Narrative
    # One slice of a progressive (per-action) narration: DM text, completion flag,
    # queue position, and the truncated action line. Not persisted — this is the
    # contract for Pipeline#on_narrative and for each element of :narratives on
    # :narrated_sequence when the queue aborts after partial per-action output.
    ProgressiveEntry = Data.define(
      :narrative,
      :adventure_complete,
      :sequence_index,
      :total_actions,
      :action_text
    ) do
      # @param phase [Hash] return value of PipelineEngine#run_narrative_phase
      def self.from_narrative_phase(phase, sequence_index:, total_actions:, action_text:)
        new(
          narrative: phase[:narrative],
          adventure_complete: phase[:adventure_complete],
          sequence_index: sequence_index,
          total_actions: total_actions,
          action_text: action_text
        )
      end
    end
  end
end
