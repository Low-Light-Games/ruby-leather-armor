# frozen_string_literal: true

module DungeonMaster
  module Narrative
    # Bundles resolver intent (single-action or merged), PipelineContext, mutations,
    # and optional Stagehand +extra+ flags for one call to Stagehand#run_narrative_phase.
    #
    # Built by SingleActionAssembly (per-action progressive queue) or
    # AccumulatedAssembly (multi-action or encounter-tail narration). The +intent+ shape
    # matches what +resolve_plot+ and narrative substeps expect in each case.
    class NarrationPhaseInputs
      attr_reader :intent, :pipeline_context, :mutations, :extra

      def initialize(intent:, pipeline_context:, mutations:, extra: nil)
        @intent            = intent
        @pipeline_context  = pipeline_context
        @mutations         = mutations
        @extra             = extra || {}
      end
    end
  end
end
