# frozen_string_literal: true

require_relative 'step_registry/entry'
require_relative 'step_registry/model_hints'

module DungeonMaster
  # Single source of truth for all AI step metadata.
  #
  # To add a new AI step: add one entry to STEPS. PlayLog::EVENT_TYPES,
  # DmConfig::TOKEN_BUDGET_STEPS, and STEP_MODEL_HINTS all derive from
  # this registry automatically.
  #
  # The `pipeline` flag controls whether a step appears in the DM config
  # admin UI (token budgets, model selection). Non-pipeline steps
  # (enricher, embellisher, embedding, rules_retrieval) are logged but
  # not configurable per-run.
  module StepRegistry
    H = ModelHints

    STEPS = {
      'intake' => Entry.new(token_budget: nil, model_hint: H::INTAKE,
                            pipeline: true),
      'dm_query' => Entry.new(token_budget: nil, model_hint: H::DM_QUERY,
                              pipeline: true),
      'sequencer' => Entry.new(token_budget: nil, model_hint: H::SEQUENCER,
                               pipeline: true),
      'sanity_checker' => Entry.new(token_budget: nil, model_hint: H::SANITY_CHECKER,
                                    pipeline: true),
      'sanity_checker_world' => Entry.new(token_budget: nil, model_hint: H::SANITY_CHECKER_WORLD,
                                          pipeline: true),
      'mechanic' => Entry.new(token_budget: nil, model_hint: H::MECHANIC,
                              pipeline: true),
      'combat_gm' => Entry.new(token_budget: 900, model_hint: H::COMBAT_GM,
                               pipeline: true),
      'momentum' => Entry.new(token_budget: nil, model_hint: H::MOMENTUM,
                              pipeline: true),
      'social_expansion' => Entry.new(token_budget: nil, model_hint: H::SOCIAL_EXPANSION,
                                      pipeline: true),
      'time_keeper' => Entry.new(token_budget: nil, model_hint: H::TIME_KEEPER,
                                 pipeline: true),
      'chronicler' => Entry.new(token_budget: nil, model_hint: H::CHRONICLER,
                                pipeline: true),
      'narrate' => Entry.new(token_budget: nil, model_hint: H::NARRATE,
                             pipeline: true),
      'micro_context_update' => Entry.new(token_budget: nil, model_hint: H::MICRO_CONTEXT_UPDATE,
                                          pipeline: true),
      'traversal_context_update' => Entry.new(token_budget: nil, model_hint: H::TRAVERSAL_CONTEXT_UPDATE,
                                              pipeline: true),
      'combat_context_update' => Entry.new(token_budget: nil, model_hint: H::COMBAT_CONTEXT_UPDATE,
                                           pipeline: true),
      'social_context_update' => Entry.new(token_budget: nil, model_hint: H::SOCIAL_CONTEXT_UPDATE,
                                           pipeline: true),
      'exploration_context_update' => Entry.new(token_budget: nil, model_hint: H::EXPLORATION_CONTEXT_UPDATE,
                                                pipeline: true),
      'rest_context_update' => Entry.new(token_budget: nil, model_hint: H::REST_CONTEXT_UPDATE,
                                         pipeline: true),
      'inventory_context_update' => Entry.new(token_budget: nil, model_hint: H::INVENTORY_CONTEXT_UPDATE,
                                              pipeline: true),
      'meta_context_update' => Entry.new(token_budget: nil, model_hint: H::META_CONTEXT_UPDATE,
                                         pipeline: true),
      'macro_narrative_update' => Entry.new(token_budget: nil, model_hint: H::MACRO_NARRATIVE_UPDATE,
                                            pipeline: true),
      'creature_generation' => Entry.new(token_budget: nil, model_hint: H::CREATURE_GENERATION,
                                         pipeline: true),
      'beacon' => Entry.new(token_budget: nil, model_hint: H::BEACON,
                            pipeline: true),
      'mechanical_evaluation' => Entry.new(token_budget: nil, model_hint: H::MECHANICAL_EVALUATION,
                                           pipeline: true),
      'roll_qualifier' => Entry.new(token_budget: nil, model_hint: H::ROLL_QUALIFIER,
                                    pipeline: true),
      'roll_request' => Entry.new(token_budget: nil, model_hint: H::ROLL_REQUEST, pipeline: true,
                                  default_model: 'gpt-5-nano', default_reasoning_effort: 'minimal'),
      'combat_roll_request' => Entry.new(token_budget: nil, model_hint: H::COMBAT_ROLL_REQUEST, pipeline: true,
                                         default_model: 'gpt-5-nano', default_reasoning_effort: 'minimal'),
      'rules_retrieval' => Entry.new(token_budget: nil, model_hint: nil,
                                     pipeline: false),
      'npc_action' => Entry.new(token_budget: 300, model_hint: H::NPC_ACTION,
                                pipeline: true),
      'loremaster' => Entry.new(token_budget: nil, model_hint: H::LOREMASTER,
                                pipeline: true),
      'embedding' => Entry.new(token_budget: nil, model_hint: nil,
                               pipeline: false),
      'encounter_expand' => Entry.new(token_budget: nil, model_hint: nil,
                                      pipeline: false),
      'enricher' => Entry.new(token_budget: nil, model_hint: nil,
                              pipeline: false),
      'embellisher' => Entry.new(token_budget: nil, model_hint: nil,
                                 pipeline: false),
      'combat_narrator' => Entry.new(token_budget: 220, model_hint: H::COMBAT_NARRATOR,
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
