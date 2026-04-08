# frozen_string_literal: true

module DungeonMaster
  module Narrative
    # Single ERB root for `narrate.text.erb`: loop, time, pacing, and PipelineContext fields.
    class NarratePromptView
      def self.for_narrate(pipeline_engine, pipeline_context)
        new(
          pipeline_context:   pipeline_context,
          loop:               pipeline_engine.loop,
          time_context:       pipeline_engine.adventure.time_context || {},
          pacing_text:        PromptHelpers.pacing_instructions(pipeline_engine.config),
          directed_play_text: PromptHelpers.directed_play_instructions(pipeline_engine.adventure)
        )
      end

      def initialize(pipeline_context:, loop:, time_context:, pacing_text:, directed_play_text:)
        @pipeline_context   = pipeline_context
        @loop               = loop
        @time_context       = time_context
        @pacing_text        = pacing_text
        @directed_play_text = directed_play_text
      end

      attr_reader :loop, :time_context, :pacing_text, :directed_play_text

      def dm_brief
        @pipeline_context.dm_brief
      end

      def combined_seed
        @pipeline_context.combined_seed
      end

      def prior_outcomes
        @pipeline_context.prior_outcomes
      end

      def player_action
        @pipeline_context.player_action
      end
    end
  end
end
