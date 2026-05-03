# frozen_string_literal: true

module DungeonMaster
  module Narrative
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
