class DmConfig < ApplicationRecord
  # Single-row configuration for the AI Dungeon Master.
  # Settings are stored as a JSON hash, making it easy to add new knobs
  # without migrations.
  TOKEN_BUDGET_STEPS = DungeonMaster::StepRegistry.pipeline_steps.freeze
  STEP_MODEL_HINTS   = DungeonMaster::StepRegistry.model_hints.freeze

  ENRICHER_MODEL_HINT = "Capable model recommended. Structural extraction benefits from strong reasoning — e.g. o3-mini, o4-mini, gpt-4.1, gpt-5-mini."
  EMBELLISHER_MODEL_HINT = "Creative model. Flavor generation benefits from vivid writing — e.g. gpt-4.1, gpt-4o, gpt-5. Expand mode benefits from reasoning — e.g. o3-mini, gpt-5-mini."
  EMBELLISHER_MODES = %w[embellish expand].freeze

  # Closed whitelist for the narrative facts store's embedding model
  # selector (see Decision 37). The `adventure_narrative_facts.embedding`
  # column is fixed at `vector(1536)`, so models with native dim > 1536
  # need `dimensions: 1536` passed to OpenAI to truncate to our column
  # width — captured here as `dimensions_override` so the read/write
  # call sites don't have to duplicate that mapping.
  EMBEDDING_MODELS = [
    {
      "id"                   => "text-embedding-3-small",
      "name"                 => "text-embedding-3-small (default)",
      "native_dimensions"    => 1536,
      "dimensions_override"  => nil,
      "input_cost"           => 0.02,
      "description"          => "Cheap, fast, 1536-d native. Good retrieval quality for the price."
    },
    {
      "id"                   => "text-embedding-3-large",
      "name"                 => "text-embedding-3-large",
      "native_dimensions"    => 3072,
      "dimensions_override"  => 1536,
      "input_cost"           => 0.13,
      "description"          => "Best OpenAI retrieval quality; native 3072-d truncated to 1536-d for our column. ~6.5× cost of -3-small."
    },
    {
      "id"                   => "text-embedding-ada-002",
      "name"                 => "text-embedding-ada-002 (legacy)",
      "native_dimensions"    => 1536,
      "dimensions_override"  => nil,
      "input_cost"           => 0.10,
      "description"          => "Previous generation; worse quality than -3-small at 5× the cost. Kept for compatibility only."
    },
  ].freeze

  EMBEDDING_MODEL_IDS = EMBEDDING_MODELS.map { |m| m["id"] }.freeze
  EMBEDDING_MODEL_HINT = "Model used to embed both stored facts (write path) and player intents (read path). Switching the model invalidates existing vectors — already-stored facts will retrieve poorly until re-embedded. Pick once and only change with a deliberate backfill plan."

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
    "temperature" => 0.8,
    "pacing_words_min" => 40,
    "pacing_words_max" => 120,
    "danger_threshold" => 30,
    "model" => "gpt-4o-mini",
    "step_models" => {},
    "embellisher_mode" => "embellish",
    "action_queue" => "progressive",
    "show_roll_dc" => true,
    "scene_history_depth" => 10,
    "chronicler_tone_direction" => false,
    "creature_creation_fallback" => "ai",
    "instant_death" => true,
    "no_auto_hit_miss" => true,
    "terrain_speed_modifiers" => {
      "road" => 1.0, "trail" => 0.75, "urban" => 1.0, "coast" => 0.75,
      "forest" => 0.5, "swamp" => 0.5, "desert" => 0.75, "river" => 0.5,
      "mountain" => 0.25, "underground" => 0.5
    },
    "wait_messages" => WAIT_MESSAGES_DEFAULT,
    "token_budgets" => {},
    "narrative_facts_top_k" => 8,
    "narrative_facts_active_window" => 20,
    "narrative_facts_embedding_model" => "text-embedding-3-small",
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

  def temperature
    get("temperature").to_f
  end

  def pacing_words_min
    get("pacing_words_min").to_i
  end

  def pacing_words_max
    get("pacing_words_max").to_i
  end

  def danger_threshold
    get("danger_threshold").to_i
  end

  def model
    get("model")
  end

  def model_for(step)
    overrides = get("step_models") || {}
    overrides[step.to_s].presence || model
  end

  def token_budget_for(step)
    budgets = get("token_budgets")
    val = budgets[step.to_s]
    val.nil? ? nil : val.to_i
  end

  def instant_death?
    get("instant_death") == true
  end

  def no_auto_hit_miss?
    get("no_auto_hit_miss") == true
  end

  def narrative_facts_top_k
    get("narrative_facts_top_k").to_i
  end

  def narrative_facts_active_window
    get("narrative_facts_active_window").to_i
  end

  def narrative_facts_embedding_model
    val = get("narrative_facts_embedding_model").to_s
    EMBEDDING_MODEL_IDS.include?(val) ? val : DEFAULTS["narrative_facts_embedding_model"]
  end

  # Returns the `dimensions:` parameter to pass to OpenAI for the
  # currently-selected embedding model, or nil when the model's native
  # dim already matches our `vector(1536)` column. Call sites pass this
  # through to `AiClient#embeddings(dimensions:)`.
  def narrative_facts_embedding_dimensions
    entry = EMBEDDING_MODELS.find { |m| m["id"] == narrative_facts_embedding_model }
    entry && entry["dimensions_override"]
  end
end
