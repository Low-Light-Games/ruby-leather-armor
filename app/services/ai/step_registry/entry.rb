# frozen_string_literal: true

module Ai
  module StepRegistry
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
