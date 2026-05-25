# frozen_string_literal: true

require_relative 'step_registry/entry'
require_relative 'step_registry/model_hints'

module Ai
  module StepRegistry
    H = ModelHints

    STEPS = {
      'intake' => Entry.new(model_hint: H::INTAKE,
                            pipeline: true),
      'game_master' => Entry.new(model_hint: H::GAME_MASTER,
                                 pipeline: true),
      'sequencer' => Entry.new(model_hint: H::SEQUENCER,
                               pipeline: true),
      'sanity_checker' => Entry.new(model_hint: H::SANITY_CHECKER,
                                    pipeline: true),
      'sanity_checker_world' => Entry.new(model_hint: H::SANITY_CHECKER_WORLD,
                                          pipeline: true),
      'mechanic' => Entry.new(model_hint: H::MECHANIC,
                              pipeline: true),
      'combat_gm' => Entry.new(model_hint: H::COMBAT_GM,
                               pipeline: true),
      'time_keeper' => Entry.new(model_hint: H::TIME_KEEPER,
                                 pipeline: true),
      'narrate' => Entry.new(model_hint: H::NARRATE,
                             pipeline: true),
      'combat_context_update' => Entry.new(model_hint: H::COMBAT_CONTEXT_UPDATE,
                                           pipeline: true),
      'roll_request' => Entry.new(model_hint: H::ROLL_REQUEST,
                                  pipeline: true),
      'cast_resolver' => Entry.new(model_hint: H::CAST_RESOLVER,
                                   pipeline: true),
      'interpreter' => Entry.new(model_hint: H::INTERPRETER,
                                 pipeline: true),
      'request_roll_tool' => Entry.new(model_hint: H::REQUEST_ROLL_TOOL,
                                       pipeline: true),
      'combat_roll_request' => Entry.new(model_hint: H::COMBAT_ROLL_REQUEST,
                                         pipeline: true),
      'loremaster' => Entry.new(model_hint: H::LOREMASTER,
                                pipeline: true),
      'social_master' => Entry.new(model_hint: H::SOCIAL_MASTER,
                                   pipeline: true),
      'geomaster' => Entry.new(model_hint: H::GEOMASTER,
                               pipeline: true),
      'ooc_responder' => Entry.new(model_hint: H::OOC_RESPONDER,
                                   pipeline: true),
      # Authoring/non-pipeline AI calls (story save-time, admin editor,
      # background data ops). Cluster together so the registry shows
      # the boundary at a glance.
      'creature_generation' => Entry.new(model_hint: H::CREATURE_GENERATION,
                                         pipeline: false),
      'extract_from_premise' => Entry.new(model_hint: H::EXTRACT_FROM_PREMISE,
                                          pipeline: false),
      'generate_opening_message' => Entry.new(model_hint: H::GENERATE_OPENING_MESSAGE,
                                              pipeline: false),
      'embedding' => Entry.new(model_hint: nil,
                               pipeline: false),
      'encounter_expand' => Entry.new(model_hint: nil,
                                      pipeline: false),
      'combat_bookend' => Entry.new(model_hint: H::COMBAT_BOOKEND,
                                    pipeline: false)
    }.freeze

    def self.all_call_types
      STEPS.keys
    end

    def self.pipeline_steps
      STEPS.select { |_, e| e.pipeline }.keys
    end

    def self.model_hints
      STEPS.select { |_, e| e.model_hint }.transform_values(&:model_hint)
    end

    def self.default_model_for(step)
      STEPS[step.to_s]&.default_model
    end

    def self.default_reasoning_effort_for(step)
      STEPS[step.to_s]&.default_reasoning_effort
    end
  end
end
