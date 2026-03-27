# frozen_string_literal: true

module DungeonMaster
  # Single source of truth for all AI step metadata.
  #
  # To add a new AI step: add one entry to STEPS. PlayLog::EVENT_TYPES,
  # DmConfig::TOKEN_BUDGET_STEPS, STEP_MODEL_HINTS, and default token
  # budgets all derive from this registry automatically.
  #
  # The `pipeline` flag controls whether a step appears in the DM config
  # admin UI (token budgets, model selection). Non-pipeline steps (enricher,
  # embellisher) are logged but not configurable per-run.
  module StepRegistry
    Entry = Data.define(:token_budget, :model_hint, :pipeline)

    STEPS = {
      "intake" => Entry.new(
        token_budget: 400,
        model_hint: "Fast, cheap model. Security + dm_query detection + context suggestion — e.g. gpt-4.1-nano, gpt-5-nano, gpt-4o-mini.",
        pipeline: true,
      ),
      "dm_query" => Entry.new(
        token_budget: 300,
        model_hint: "Fast, cheap model. Straightforward Q&A — e.g. gpt-4.1-nano, gpt-5-nano, gpt-4o-mini.",
        pipeline: true,
      ),
      "sequencer" => Entry.new(
        token_budget: 200,
        model_hint: "Fast, cheap model. Compound action detection — e.g. gpt-4.1-nano, gpt-5-nano, gpt-4o-mini.",
        pipeline: true,
      ),
      "sanity_checker" => Entry.new(
        token_budget: 300,
        model_hint: "Fast, cheap model. Sheet validation — e.g. gpt-4.1-nano, gpt-5-nano, gpt-4o-mini. Only used in AI mode.",
        pipeline: true,
      ),
      "sanity_checker_world" => Entry.new(
        token_budget: 500,
        model_hint: "⚠️ Capable model REQUIRED. Cross-references player actions against full game state. Unlikely to perform well with budget models. Recommended: gpt-4o-mini or better (gpt-4.1-mini, o3-mini, gpt-5-mini).",
        pipeline: true,
      ),
      "mechanic" => Entry.new(
        token_budget: 600,
        model_hint: "➡️ Capable model suggested. Post-roll arbitration and mutation generation — e.g. o3-mini, o4-mini, gpt-5-mini.",
        pipeline: true,
      ),
      "momentum" => Entry.new(
        token_budget: 500,
        model_hint: "Mid-tier model. Non-mechanical outcome determination and context-domain assessment — e.g. gpt-4.1-mini, gpt-4o-mini, gpt-5-nano.",
        pipeline: true,
      ),
      "social_expansion" => Entry.new(
        token_budget: 500,
        model_hint: "Mid-tier model. Scene creation with NPC personality and attitude — e.g. gpt-4.1-mini, gpt-4o-mini, gpt-5-nano.",
        pipeline: true,
      ),
      "time_keeper" => Entry.new(
        token_budget: 300,
        model_hint: "Fast, cheap model. Estimates in-game time for an action — e.g. gpt-4.1-nano, gpt-5-nano, gpt-4o-mini.",
        pipeline: true,
      ),
      "chronicler" => Entry.new(
        token_budget: 500,
        model_hint: "➡️ Capable model suggested. Receives social, traversal, and exploration context; condition matching and scene-aware NPC reactions. Use a capable model and sufficient token budget — e.g. gpt-4.1-mini, gpt-4o-mini, o3-mini.",
        pipeline: true,
      ),
      "narrate" => Entry.new(
        token_budget: 800,
        model_hint: "Creative model. Narrative quality scales with capability — e.g. gpt-4.1, gpt-4o, gpt-5.",
        pipeline: true,
      ),
      "micro_context_update" => Entry.new(
        token_budget: 1500,
        model_hint: "Mid-tier model. Structured JSON with moderate judgment — e.g. gpt-4.1-mini, gpt-4o-mini, gpt-5-nano.",
        pipeline: true,
      ),
      "macro_narrative_update" => Entry.new(
        token_budget: 500,
        model_hint: "Mid-tier model. Judges narrative significance — e.g. gpt-4.1-mini, gpt-4o-mini, gpt-5-nano.",
        pipeline: true,
      ),
      "creature_generation" => Entry.new(
        token_budget: 600,
        model_hint: "Mid-tier model recommended. Must produce valid PF1e stat blocks — e.g. gpt-4.1-mini, gpt-4o-mini, o3-mini.",
        pipeline: true,
      ),
      "beacon" => Entry.new(
        token_budget: 400,
        model_hint: "Fast, cheap model. Per-domain intent classification — runs 6 in parallel via the Node evaluator microservice. e.g. gpt-4.1-nano, gpt-4o-mini, gpt-4.1-mini.",
        pipeline: true,
      ),
      "mechanical_evaluation" => Entry.new(
        token_budget: 600,
        model_hint: "Mid-tier model. Per-domain mechanical resolution, run sequentially with cross-domain awareness via the Node evaluator microservice. e.g. gpt-4.1-mini, gpt-4o-mini, o3-mini.",
        pipeline: true,
      ),
      "roll_qualifier" => Entry.new(
        token_budget: 300,
        model_hint: "Fast, cheap model. Determines Take 10/20 eligibility and situational modifiers. Run in parallel per domain via the Node evaluator microservice. e.g. gpt-4.1-nano, gpt-4o-mini.",
        pipeline: true,
      ),
      "encounter_expand" => Entry.new(
        token_budget: nil,
        model_hint: nil,
        pipeline: false,
      ),
      "enricher" => Entry.new(
        token_budget: nil,
        model_hint: nil,
        pipeline: false,
      ),
      "embellisher" => Entry.new(
        token_budget: nil,
        model_hint: nil,
        pipeline: false,
      ),
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

    def self.default_token_budgets
      STEPS.select { |_, e| e.token_budget }.transform_values(&:token_budget)
    end
  end
end
