class DmConfig < ApplicationRecord
  # Single-row configuration for the AI Dungeon Master.
  # Settings are stored as a JSON hash, making it easy to add new knobs
  # without migrations.
  TOKEN_BUDGET_STEPS = DungeonMaster::StepRegistry.pipeline_steps.freeze
  STEP_MODEL_HINTS   = DungeonMaster::StepRegistry.model_hints.freeze

  EVALUATION_MODES = %w[standard unified].freeze

  ENRICHER_MODEL_HINT = "Capable model recommended. Structural extraction benefits from strong reasoning — e.g. o3-mini, o4-mini, gpt-4.1, gpt-5-mini."
  EMBELLISHER_MODEL_HINT = "Creative model. Flavor generation benefits from vivid writing — e.g. gpt-4.1, gpt-4o, gpt-5. Expand mode benefits from reasoning — e.g. o3-mini, gpt-5-mini."
  EMBELLISHER_MODES = %w[off embellish expand].freeze

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
    "token_budgets" => DungeonMaster::StepRegistry.default_token_budgets,
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
