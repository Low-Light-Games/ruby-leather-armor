class DmConfig < ApplicationRecord
  # Single-row configuration for the AI Dungeon Master.
  # Settings are stored as a JSON hash, making it easy to add new knobs
  # without migrations.
  TOKEN_BUDGET_STEPS = %w[
    intake dm_query sequencer player_interpreter beacon mechanical_evaluation
    roll_qualifier sanity_checker sanity_checker_world mechanic momentum time_keeper
    social_expansion chronicler narrate
    micro_context_update macro_narrative_update
    edge_pipeline creature_generation unified_evaluation
  ].freeze

  EVALUATION_MODES = %w[standard unified].freeze

  ENRICHER_MODEL_HINT = "Capable model recommended. Structural extraction benefits from strong reasoning — e.g. o3-mini, o4-mini, gpt-4.1, gpt-5-mini."
  EMBELLISHER_MODEL_HINT = "Creative model. Flavor generation benefits from vivid writing — e.g. gpt-4.1, gpt-4o, gpt-5. Expand mode benefits from reasoning — e.g. o3-mini, gpt-5-mini."
  EMBELLISHER_MODES = %w[off embellish expand].freeze

  STEP_MODEL_HINTS = {
    "intake"                 => "Fast, cheap model. Security + dm_query detection + context suggestion — e.g. gpt-4.1-nano, gpt-5-nano, gpt-4o-mini.",
    "dm_query"               => "Fast, cheap model. Straightforward Q&A — e.g. gpt-4.1-nano, gpt-5-nano, gpt-4o-mini.",
    "sequencer"              => "Fast, cheap model. Compound action detection — e.g. gpt-4.1-nano, gpt-5-nano, gpt-4o-mini.",
    "player_interpreter"     => "Fast, cheap model. Simple restatement — e.g. gpt-4.1-nano, gpt-5-nano, gpt-4o-mini.",
    "beacon"                 => "Fast, cheap model. Per-domain interpretation — e.g. gpt-4.1-nano, gpt-5-nano, gpt-4o-mini.",
    "mechanical_evaluation"  => "➡️ Capable model suggested. Rules adjudication across domains; must catch required rolls and consequences from context. Use a capable model — e.g. o3-mini, o4-mini, gpt-5-mini.",
    "roll_qualifier"         => "Fast, cheap model with broader context. Situational modifiers and Take 10/20 — e.g. gpt-4.1-nano, gpt-4o-mini.",
    "sanity_checker"         => "Fast, cheap model. Sheet validation — e.g. gpt-4.1-nano, gpt-5-nano, gpt-4o-mini. Only used in AI mode.",
    "sanity_checker_world"   => "⚠️ Capable model REQUIRED. Cross-references player actions against full game state. Unlikely to perform well with budget models. Recommended: gpt-4o-mini or better (gpt-4.1-mini, o3-mini, gpt-5-mini).",
    "mechanic"               => "➡️ Capable model suggested. Post-roll arbitration and mutation generation — e.g. o3-mini, o4-mini, gpt-5-mini.",
    "momentum"               => "Mid-tier model. Non-mechanical outcome determination and context-domain assessment — e.g. gpt-4.1-mini, gpt-4o-mini, gpt-5-nano.",
    "social_expansion"       => "Mid-tier model. Scene creation with NPC personality and attitude — e.g. gpt-4.1-mini, gpt-4o-mini, gpt-5-nano.",
    "time_keeper"            => "Fast, cheap model. Estimates in-game time for an action — e.g. gpt-4.1-nano, gpt-5-nano, gpt-4o-mini.",
    "chronicler"             => "➡️ Capable model suggested. Receives social, traversal, and exploration context; condition matching and scene-aware NPC reactions. Use a capable model and sufficient token budget — e.g. gpt-4.1-mini, gpt-4o-mini, o3-mini.",
    "narrate"                => "Creative model. Narrative quality scales with capability — e.g. gpt-4.1, gpt-4o, gpt-5.",
    "micro_context_update"   => "Mid-tier model. Structured JSON with moderate judgment — e.g. gpt-4.1-mini, gpt-4o-mini, gpt-5-nano.",
    "macro_narrative_update" => "Mid-tier model. Judges narrative significance — e.g. gpt-4.1-mini, gpt-4o-mini, gpt-5-nano.",
    "edge_pipeline"          => "Capable, creative model. Handles everything in one call — e.g. gpt-4.1, gpt-4o, gpt-5, o3-mini.",
    "creature_generation"    => "Mid-tier model recommended. Must produce valid PF1e stat blocks — e.g. gpt-4.1-mini, gpt-4o-mini, o3-mini.",
    "unified_evaluation"     => "⚠️ Top-end model REQUIRED. Single-call beacon+mecheval+rollqualifier across all domains. Requires strong cross-domain reasoning — e.g. o3, gpt-5, claude-4-opus."
  }.freeze

  CREATURE_CREATION_FALLBACKS = %w[ai template none].freeze

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
    "pacing_words_min" => 40,
    "pacing_words_max" => 120,
    "danger_threshold" => 30,
    "model" => "gpt-4o-mini",
    "step_models" => {},
    "embellisher_mode" => "embellish",
    "pipeline_mode" => "budget",
    "guardrail_mode" => "code",
    "narration_mode" => "parallel",
    "action_queue" => true,
    "async_pipeline" => false,
    "show_roll_dc" => true,
    "evaluation_mode" => "standard",
    "roll_qualifier_scope" => "domain",
    "scene_history_depth" => 10,
    "chronicler_tone_direction" => false,
    "creature_creation_fallback" => "ai",
    "terrain_speed_modifiers" => {
      "road" => 1.0, "trail" => 0.75, "urban" => 1.0, "coast" => 0.75,
      "forest" => 0.5, "swamp" => 0.5, "desert" => 0.75, "river" => 0.5,
      "mountain" => 0.25, "underground" => 0.5
    },
    "wait_messages" => WAIT_MESSAGES_DEFAULT,
    "token_budgets" => {
      "intake" => 400,
      "dm_query" => 300,
      "sequencer" => 200,
      "player_interpreter" => 200,
      "beacon" => 400,
      "mechanical_evaluation" => 500,
      "roll_qualifier" => 400,
      "sanity_checker" => 300,
      "sanity_checker_world" => 500,
      "mechanic" => 600,
      "momentum" => 500,
      "social_expansion" => 500,
      "time_keeper" => 300,
      "chronicler" => 500,
      "narrate" => 800,
      "micro_context_update" => 800,
      "macro_narrative_update" => 500,
      "edge_pipeline" => 2000,
      "creature_generation" => 600,
      "unified_evaluation" => 1500
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

  def danger_threshold
    (get("danger_threshold") || get("sanitization_threshold") || 30).to_i
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
