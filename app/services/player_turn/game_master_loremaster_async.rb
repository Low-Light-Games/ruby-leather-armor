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

      loremaster_inputs = Steps::Loremaster::Inputs.new(
        what_happened: @narrative.to_s,
        active_facts: active_facts_window,
      )
      social_master_inputs = build_social_master_inputs(@narrative)
      geomaster_inputs     = build_geomaster_inputs(@narrative)

      prompts = [
        Steps::Loremaster.turn_evaluator_prompt(inputs: loremaster_inputs, config: @config),
        Steps::SocialMaster.turn_evaluator_prompt(inputs: social_master_inputs, config: @config),
        Steps::Geomaster.turn_evaluator_prompt(inputs: geomaster_inputs, config: @config),
      ]
      by_step = evaluator_fan_out!(prompts, @narrative, phase: "game_master_loremaster")

      apply_loremaster_from_fan_out!(by_step)
      apply_social_master_from_fan_out!(by_step)
      apply_geomaster_from_fan_out!(by_step)
    end
  end
end
