# frozen_string_literal: true

module DungeonMaster
  module Narrative
    # One slice of a progressive (per-action) narration: DM text, completion flag,
    # queue position, and the truncated action line. Not persisted — this is the
    # contract for PipelineEngine#on_narrative and for each element of :narratives on
    # :narrated_sequence when the queue aborts after partial per-action output.
    class ProgressiveEntry
      attr_reader :narrative, :adventure_complete, :player_death, :player_incapacitated, :sequence_index, :total_actions, :action_text

      def initialize(narrative:, adventure_complete:, player_death: false, player_incapacitated: false, sequence_index:, total_actions:, action_text:)
        @narrative          = narrative
        @adventure_complete = adventure_complete
        @player_death       = player_death
        @player_incapacitated = player_incapacitated
        @sequence_index     = sequence_index
        @total_actions      = total_actions
        @action_text        = action_text
      end

      # @param phase [Hash] return value of PipelineEngine#run_narrative_phase
      def self.from_narrative_phase(phase, sequence_index:, total_actions:, action_text:)
        new(
          narrative: phase[:narrative],
          adventure_complete: phase[:adventure_complete],
          player_death: phase[:player_death] == true,
          player_incapacitated: phase[:player_incapacitated] == true,
          sequence_index: sequence_index,
          total_actions: total_actions,
          action_text: action_text
        )
      end

      def to_h
        {
          narrative: narrative,
          adventure_complete: adventure_complete,
          player_death: player_death,
          player_incapacitated: player_incapacitated,
          sequence_index: sequence_index,
          total_actions: total_actions,
          action_text: action_text
        }
      end
    end
  end
end
