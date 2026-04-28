# frozen_string_literal: true

module DungeonMaster
  module StepRegistry
    # One row of step metadata: token budget, admin UI model hint,
    # default model + reasoning_effort, and whether the step is
    # configurable from the DM config admin UI.
    #
    # `default_model` lets a step pin its preferred model independently
    # of the global `DmConfig#model` default. Consulted by
    # `DmConfig#model_for` when no admin override exists. nil means
    # "use the global default".
    #
    # `default_reasoning_effort` is the fallback `reasoning_effort`
    # ("minimal"|"low"|"medium"|"high") sent to OpenAI when the
    # resolved model is a reasoning model AND no admin override is set
    # in `DmConfig#step_reasoning_efforts`. nil means "use the OpenAI
    # default".
    class Entry
      attr_reader :token_budget, :model_hint, :pipeline, :default_model, :default_reasoning_effort

      def initialize(token_budget:, model_hint:, pipeline:, default_model: nil, default_reasoning_effort: nil)
        @token_budget = token_budget
        @model_hint = model_hint
        @pipeline = pipeline
        @default_model = default_model
        @default_reasoning_effort = default_reasoning_effort
      end
    end
  end
end
