# frozen_string_literal: true

module DungeonMaster
  module Narrative
    # Builds PipelineContext for progressive (per-action) narration: one AdventureLoop row’s
    # +pipeline_outcome+, optional prior outcomes for +progressive_continuity+, and plot brief.
    class SingleActionAssembly
      Result = Struct.new(:intent, :pipeline_context, :mutations, keyword_init: true)

      def self.call(pipeline:, result:, progressive_continuity:)
        loop = pipeline.loop
        outcome = loop&.get("pipeline_outcome")
        plot_result = pipeline.send(:resolve_plot, result[:intent], verdict_outcome: outcome)

        prior = if progressive_continuity
                  AdventureLoop.prior_pipeline_outcomes_before(
                    pipeline_run_id: pipeline.log.pipeline_run_id,
                    current_loop: loop)
                else
                  []
                end

        ctx = PipelineContext.new(
          combined_seed: outcome,
          dm_brief: plot_result&.dig(:dm_brief),
          player_action: loop&.player_intent,
          prior_outcomes: prior
        )

        Result.new(
          intent: result[:intent],
          pipeline_context: ctx,
          mutations: result[:mutations]
        )
      end
    end
  end
end
