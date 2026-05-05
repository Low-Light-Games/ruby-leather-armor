# frozen_string_literal: true

require_relative 'step_registry/entry'
require_relative 'step_registry/model_hints'

module DungeonMaster
  # Single source of truth for all AI step metadata.
  #
  # To add a new AI step: add one entry to STEPS. PlayLog::EVENT_TYPES and
  # STEP_MODEL_HINTS derive from this registry automatically.
  #
  # The `pipeline` flag controls whether a step appears in the DM config
  # admin UI (model selection). Non-pipeline steps (embedding,
  # rules_retrieval, encounter_expand, extract_from_premise) are logged
  # but not configurable per-run.
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
      'macro_narrative_update' => Entry.new(model_hint: H::MACRO_NARRATIVE_UPDATE,
                                            pipeline: true),
      'creature_generation' => Entry.new(model_hint: H::CREATURE_GENERATION,
                                         pipeline: true),
      'extract_from_premise' => Entry.new(model_hint: H::EXTRACT_FROM_PREMISE,
                                          pipeline: false),
      'generate_opening_message' => Entry.new(model_hint: H::GENERATE_OPENING_MESSAGE,
                                              pipeline: false),
      'roll_request' => Entry.new(model_hint: H::ROLL_REQUEST,
                                  pipeline: true),
      'combat_roll_request' => Entry.new(model_hint: H::COMBAT_ROLL_REQUEST,
                                         pipeline: true),
      'rules_retrieval' => Entry.new(model_hint: nil,
                                     pipeline: false),
      'loremaster' => Entry.new(model_hint: H::LOREMASTER,
                                pipeline: true),
      'embedding' => Entry.new(model_hint: nil,
                               pipeline: false),
      'encounter_expand' => Entry.new(model_hint: nil,
                                      pipeline: false),
      'combat_narrator' => Entry.new(model_hint: H::COMBAT_NARRATOR,
                                     pipeline: true)
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

    # Step → preferred default model, for steps that pin one. Consulted
    # by `DmConfig#model_for` before falling back to the global default.
    def self.default_model_for(step)
      STEPS[step.to_s]&.default_model
    end

    # Step → preferred default `reasoning_effort`, for steps that pin
    # one. Consulted by `DmConfig#reasoning_effort_for` when no admin
    # override is set.
    def self.default_reasoning_effort_for(step)
      STEPS[step.to_s]&.default_reasoning_effort
    end
  end
end
