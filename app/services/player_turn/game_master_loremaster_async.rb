# frozen_string_literal: true

module PlayerTurn
  class GameMasterLoremasterAsync
    include Steps::EvaluatorTransport
    include Steps::Stagehand

    def self.call(adventure:, config:, ai:, log:, narrative:, loop: nil)
      new(
        adventure: adventure,
        config: config,
        ai: ai,
        log: log,
        narrative: narrative,
        loop: loop
      ).call
    end

    def initialize(adventure:, config:, ai:, log:, narrative:, loop:)
      @adventure = adventure
      @config = config
      @ai = ai
      @log = log
      @narrative = narrative
      @loop = loop
    end

    def call
      return if @narrative.blank?

      inputs = Steps::LoremasterInputs.new(
        what_happened: @narrative.to_s,
        mutations: {},
        active_facts: active_facts_window
      )

      prompts = [Steps::Loremaster.turn_evaluator_prompt(inputs: inputs, config: @config)]
      by_step = evaluator_fan_out!(prompts, @narrative, phase: "game_master_loremaster")
      apply_loremaster_from_fan_out!(by_step)
    end
  end
end
