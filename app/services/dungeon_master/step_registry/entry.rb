# frozen_string_literal: true

module DungeonMaster
  module StepRegistry
    # TODO: Improve readability — fallback semantics belong on DmConfig#model_for / #reasoning_effort_for, not narrated on this PORO.
    class Entry
      attr_reader :model_hint, :pipeline, :default_model, :default_reasoning_effort

      def initialize(model_hint:, pipeline:, default_model: nil, default_reasoning_effort: nil)
        @model_hint = model_hint
        @pipeline = pipeline
        @default_model = default_model
        @default_reasoning_effort = default_reasoning_effort
      end
    end
  end
end
