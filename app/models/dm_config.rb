class DmConfig < ApplicationRecord
  # Single-row configuration for the AI Dungeon Master.
  # Settings are stored as a JSON hash, making it easy to add new knobs
  # without migrations.
  TOKEN_BUDGET_STEPS = %w[
    sanitize classify dm_query intent dispatcher mechanical_evaluation
    roll_qualifier capability_guardrail ruling chronicler narrate
    micro_context_update macro_narrative_update
    edge_pipeline
  ].freeze

  ENRICHER_MODEL_HINT = "Capable model recommended. Structural extraction benefits from strong reasoning — e.g. o3-mini, o4-mini, gpt-4.1, gpt-5-mini."
  EMBELLISHER_MODEL_HINT = "Creative model. Flavor generation benefits from vivid writing — e.g. gpt-4.1, gpt-4o, gpt-5. Expand mode benefits from reasoning — e.g. o3-mini, gpt-5-mini."
  EMBELLISHER_MODES = %w[off embellish expand].freeze

  STEP_MODEL_HINTS = {
    "sanitize"               => "Fast, cheap model. Security scoring — e.g. gpt-4.1-nano, gpt-5-nano, gpt-4o-mini.",
    "classify"               => "Fast, cheap model. Simple classification — e.g. gpt-4.1-nano, gpt-5-nano, gpt-4o-mini.",
    "dm_query"               => "Fast, cheap model. Straightforward Q&A — e.g. gpt-4.1-nano, gpt-5-nano, gpt-4o-mini.",
    "intent"                 => "Fast, cheap model. Simple restatement — e.g. gpt-4.1-nano, gpt-5-nano, gpt-4o-mini.",
    "dispatcher"             => "Fast, cheap model. Per-domain interpretation — e.g. gpt-4.1-nano, gpt-5-nano, gpt-4o-mini.",
    "mechanical_evaluation"  => "Capable model. Determines required rolls and NPC actions — e.g. o3-mini, o4-mini, gpt-5-mini.",
    "roll_qualifier"         => "Fast, cheap model with broader context. Situational modifiers and Take 10/20 — e.g. gpt-4.1-nano, gpt-4o-mini.",
    "capability_guardrail"   => "Fast, cheap model. Sheet validation — e.g. gpt-4.1-nano, gpt-5-nano, gpt-4o-mini. Only used in AI mode.",
    "ruling"                 => "Capable model. Post-roll arbitration and mutation generation — e.g. o3-mini, o4-mini, gpt-5-mini.",
    "chronicler"             => "Mid-tier model. Condition matching with structured output — e.g. gpt-4.1-mini, gpt-4o-mini, o3-mini.",
    "narrate"                => "Creative model. Narrative quality scales with capability — e.g. gpt-4.1, gpt-4o, gpt-5.",
    "micro_context_update"   => "Mid-tier model. Structured JSON with moderate judgment — e.g. gpt-4.1-mini, gpt-4o-mini, gpt-5-nano.",
    "macro_narrative_update" => "Mid-tier model. Judges narrative significance — e.g. gpt-4.1-mini, gpt-4o-mini, gpt-5-nano.",
    "edge_pipeline"          => "Capable, creative model. Handles everything in one call — e.g. gpt-4.1, gpt-4o, gpt-5, o3-mini."
  }.freeze

  ROLL_QUALIFIER_SCOPES = %w[all domain dynamic social_traversal traversal_combat scene].freeze

  WAIT_MESSAGES_DEFAULT = [
    "Sculpting nightmarish creatures from clay...",
    "Convincing the universe to exist...",
    "Teaching goblins to read...",
    "Populating taverns with suspicious characters...",
    "Rolling for initiative on your behalf...",
    "Brewing mysterious potions...",
    "Arguing with a dragon about property taxes...",
    "Consulting ancient tomes of forbidden knowledge...",
    "Hiring bards to compose your theme song...",
    "Placing traps in convenient locations...",
    "Negotiating with the dungeon's landlord...",
    "Convincing mimics to hold still...",
    "Calibrating the alignment of the stars...",
    "Sharpening every sword in the kingdom...",
    "Asking the oracle for directions...",
  ].freeze

  DEFAULTS = {
    "verbose" => false,
    "temperature" => 0.8,
    "pacing_words_min" => 80,
    "pacing_words_max" => 150,
    "sanitization_threshold" => 30,
    "model" => "gpt-4o-mini",
    "step_models" => {},
    "embellisher_mode" => "embellish",
    "pipeline_mode" => "budget",
    "interpreter_scope" => "all",
    "guardrail_mode" => "code",
    "narration_mode" => "parallel",
    "async_pipeline" => false,
    "show_roll_dc" => true,
    "roll_qualifier_scope" => "domain",
    "wait_messages" => WAIT_MESSAGES_DEFAULT,
    "token_budgets" => {
      "sanitize" => 300,
      "classify" => 200,
      "dm_query" => 300,
      "intent" => 200,
      "dispatcher" => 400,
      "mechanical_evaluation" => 500,
      "roll_qualifier" => 400,
      "capability_guardrail" => 300,
      "ruling" => 600,
      "chronicler" => 500,
      "narrate" => 800,
      "micro_context_update" => 800,
      "macro_narrative_update" => 500,
      "edge_pipeline" => 2000
    }
  }.freeze

  def self.instance
    first_or_create!(settings: DEFAULTS)
  end

  def get(key)
    val = settings[key.to_s]
    val.nil? ? DEFAULTS[key.to_s] : val
  end

  def set(key, value)
    self.settings = settings.merge(key.to_s => value)
  end

  def verbose?
    get("verbose") == true
  end

  def temperature
    (get("temperature") || 0.8).to_f
  end

  def pacing_words_min
    (get("pacing_words_min") || 80).to_i
  end

  def pacing_words_max
    (get("pacing_words_max") || 150).to_i
  end

  def sanitization_threshold
    (get("sanitization_threshold") || 30).to_i
  end

  def model
    get("model") || "gpt-4o-mini"
  end

  def model_for(step)
    overrides = get("step_models") || {}
    overrides[step.to_s].presence || model
  end

  def token_budget_for(step)
    budgets = get("token_budgets") || DEFAULTS["token_budgets"]
    (budgets[step.to_s] || 500).to_i
  end
end
