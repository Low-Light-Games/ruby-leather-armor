# frozen_string_literal: true

module DungeonMaster
  # Single source of truth for all AI step metadata.
  #
  # To add a new AI step: add one entry to STEPS. PlayLog::EVENT_TYPES,
  # DmConfig::TOKEN_BUDGET_STEPS, and STEP_MODEL_HINTS all derive from
  # this registry automatically.
  #
  # The `pipeline` flag controls whether a step appears in the DM config
  # admin UI (token budgets, model selection). Non-pipeline steps (enricher,
  # embellisher) are logged but not configurable per-run.
  module StepRegistry
    # One row in STEPS: token budget, admin UI model hint, and whether the step is pipeline-configurable.
    class Entry
      attr_reader :token_budget, :model_hint, :pipeline

      def initialize(token_budget:, model_hint:, pipeline:)
        @token_budget = token_budget
        @model_hint   = model_hint
        @pipeline     = pipeline
      end
    end

    STEPS = {
      'intake' => Entry.new(
        token_budget: nil,
        model_hint: 'Fast, cheap model. Security + dm_query detection + context suggestion — e.g. gpt-4.1-nano, gpt-5-nano, gpt-4o-mini.',
        pipeline: true
      ),
      'dm_query' => Entry.new(
        token_budget: nil,
        model_hint: 'Fast, cheap model. Straightforward Q&A — e.g. gpt-4.1-nano, gpt-5-nano, gpt-4o-mini.',
        pipeline: true
      ),
      'sequencer' => Entry.new(
        token_budget: nil,
        model_hint: 'Fast, cheap model. Compound action detection — e.g. gpt-4.1-nano, gpt-5-nano, gpt-4o-mini.',
        pipeline: true
      ),
      'sanity_checker' => Entry.new(
        token_budget: nil,
        model_hint: 'Fast, cheap model. Sheet validation — e.g. gpt-4.1-nano, gpt-5-nano, gpt-4o-mini. Only used in AI mode.',
        pipeline: true
      ),
      'sanity_checker_world' => Entry.new(
        token_budget: nil,
        model_hint: '⚠️ Capable model REQUIRED. Cross-references player actions against full game state. Unlikely to perform well with budget models. Recommended: gpt-4o-mini or better (gpt-4.1-mini, o3-mini, gpt-5-mini).',
        pipeline: true
      ),
      'mechanic' => Entry.new(
        token_budget: nil,
        model_hint: '➡️ Capable model suggested. Post-roll arbitration and mutation generation — e.g. o3-mini, o4-mini, gpt-5-mini.',
        pipeline: true
      ),
      'combat_gm' => Entry.new(
        token_budget: 900,
        model_hint: '➡️ Capable model required for active combat adjudication (battlefield + PF1e) — e.g. o3-mini, gpt-5-mini.',
        pipeline: true
      ),
      'momentum' => Entry.new(
        token_budget: nil,
        model_hint: 'Mid-tier model. Non-mechanical outcome determination and context-domain assessment — e.g. gpt-4.1-mini, gpt-4o-mini, gpt-5-nano.',
        pipeline: true
      ),
      'social_expansion' => Entry.new(
        token_budget: nil,
        model_hint: 'Mid-tier model. Scene creation with NPC personality and attitude — e.g. gpt-4.1-mini, gpt-4o-mini, gpt-5-nano.',
        pipeline: true
      ),
      'time_keeper' => Entry.new(
        token_budget: nil,
        model_hint: 'Fast, cheap model. Estimates in-game time for an action — e.g. gpt-4.1-nano, gpt-5-nano, gpt-4o-mini.',
        pipeline: true
      ),
      'chronicler' => Entry.new(
        token_budget: nil,
        model_hint: '➡️ Capable model suggested. Receives social, traversal, and exploration context; condition matching and scene-aware NPC reactions. Use a capable model and sufficient token budget — e.g. gpt-4.1-mini, gpt-4o-mini, o3-mini.',
        pipeline: true
      ),
      'narrate' => Entry.new(
        token_budget: nil,
        model_hint: 'Creative model. Narrative quality scales with capability — e.g. gpt-4.1, gpt-4o, gpt-5.',
        pipeline: true
      ),
      'micro_context_update' => Entry.new(
        token_budget: nil,
        model_hint: 'Mid-tier model. Structured JSON with moderate judgment — e.g. gpt-4.1-mini, gpt-4o-mini, gpt-5-nano.',
        pipeline: true
      ),
      'traversal_context_update' => Entry.new(
        token_budget: nil,
        model_hint: 'Mid-tier model. Domain-scoped traversal JSON update — e.g. gpt-4.1-mini, gpt-4o-mini, gpt-5-nano.',
        pipeline: true
      ),
      'combat_context_update' => Entry.new(
        token_budget: nil,
        model_hint: 'Mid-tier model. Domain-scoped combat JSON update that must preserve canonical combat identity — e.g. gpt-4.1-mini, gpt-4o-mini, gpt-5-nano.',
        pipeline: true
      ),
      'social_context_update' => Entry.new(
        token_budget: nil,
        model_hint: 'Mid-tier model. Domain-scoped social JSON update — e.g. gpt-4.1-mini, gpt-4o-mini, gpt-5-nano.',
        pipeline: true
      ),
      'exploration_context_update' => Entry.new(
        token_budget: nil,
        model_hint: 'Mid-tier model. Domain-scoped exploration JSON update — e.g. gpt-4.1-mini, gpt-4o-mini, gpt-5-nano.',
        pipeline: true
      ),
      'rest_context_update' => Entry.new(
        token_budget: nil,
        model_hint: 'Mid-tier model. Domain-scoped rest JSON update — e.g. gpt-4.1-mini, gpt-4o-mini, gpt-5-nano.',
        pipeline: true
      ),
      'inventory_context_update' => Entry.new(
        token_budget: nil,
        model_hint: 'Mid-tier model. Domain-scoped inventory JSON update — e.g. gpt-4.1-mini, gpt-4o-mini, gpt-5-nano.',
        pipeline: true
      ),
      'meta_context_update' => Entry.new(
        token_budget: nil,
        model_hint: 'Fast, cheap model. Scene summary and auxiliary context signals — e.g. gpt-4.1-nano, gpt-4o-mini, gpt-5-nano.',
        pipeline: true
      ),
      'macro_narrative_update' => Entry.new(
        token_budget: nil,
        model_hint: 'Mid-tier model. Judges narrative significance — e.g. gpt-4.1-mini, gpt-4o-mini, gpt-5-nano.',
        pipeline: true
      ),
      'creature_generation' => Entry.new(
        token_budget: nil,
        model_hint: 'Mid-tier model recommended. Must produce valid PF1e stat blocks — e.g. gpt-4.1-mini, gpt-4o-mini, o3-mini.',
        pipeline: true
      ),
      'beacon' => Entry.new(
        token_budget: nil,
        model_hint: 'Fast, cheap model. Per-domain intent classification — runs 6 in parallel via the Node evaluator microservice. e.g. gpt-4.1-nano, gpt-4o-mini, gpt-4.1-mini.',
        pipeline: true
      ),
      'mechanical_evaluation' => Entry.new(
        token_budget: nil,
        model_hint: 'Mid-tier model. Per-domain mechanical resolution, run sequentially with cross-domain awareness via the Node evaluator microservice. e.g. gpt-4.1-mini, gpt-4o-mini, o3-mini.',
        pipeline: true
      ),
      'roll_qualifier' => Entry.new(
        token_budget: nil,
        model_hint: 'Fast, cheap model. Determines Take 10/20 eligibility and situational modifiers. Run in parallel per domain via the Node evaluator microservice. e.g. gpt-4.1-nano, gpt-4o-mini.',
        pipeline: true
      ),
      'roll_request' => Entry.new(
        token_budget: nil,
        model_hint: 'Fast, cheap model. Single-call replacement for beacon→mech_eval→roll_qualifier. Decides if a roll is needed and emits one roll spec, with rules retrieved via RAG and beats from the narrative facts store. No character block in prompt — code resolves modifiers post-call. e.g. gpt-4.1-nano, gpt-5-nano, gpt-4o-mini.',
        pipeline: true
      ),
      'rules_retrieval' => Entry.new(
        # Logged event_type for `play_log!("rules_retrieved", ...)` rows
        # written by `Rules::Lookup`. Not configurable — registered so
        # PlayLog::EVENT_TYPES recognizes the event.
        token_budget: nil,
        model_hint: nil,
        pipeline: false
      ),
      'npc_action' => Entry.new(
        token_budget: 300,
        model_hint: 'Fast, cheap model. Per-NPC combat action decision. Runs N in parallel via Node fan_out. e.g. gpt-4.1-nano, gpt-4o-mini.',
        pipeline: true
      ),
      'loremaster' => Entry.new(
        token_budget: nil,
        model_hint: 'Mid-tier model. Structured fact extraction from factual outcomes — e.g. gpt-4o-mini, gpt-4.1-mini, gpt-5-nano. Runs in parallel with Narrate/ContextUpdate, so latency is Narrate-bounded.',
        pipeline: true
      ),
      'embedding' => Entry.new(
        # Not a pipeline step in the LLM-chat sense — this registers
        # `call_type: "embedding"` as a known event_type for AiLog rows
        # written by `Lore::ApplyResults` (write-side) and
        # `Lore::FactsLookup` (read-side). `AiClient#embeddings` itself
        # does not write any AiLog rows.
        token_budget: nil,
        model_hint: nil,
        pipeline: false
      ),
      'encounter_expand' => Entry.new(
        token_budget: nil,
        model_hint: nil,
        pipeline: false
      ),
      'enricher' => Entry.new(
        token_budget: nil,
        model_hint: nil,
        pipeline: false
      ),
      'embellisher' => Entry.new(
        token_budget: nil,
        model_hint: nil,
        pipeline: false
      )
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
  end
end
