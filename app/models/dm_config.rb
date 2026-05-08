# frozen_string_literal: true

class DmConfig < ApplicationRecord
  # Single-row configuration for the AI Dungeon Master.
  # Settings are stored as a JSON hash, making it easy to add new knobs
  # without migrations.
  #
  # NOTE: per-step model + reasoning_effort live in
  # `config/dm_step_models.yml` (read via `DmStepModelsConfig`), not in
  # this DB row. `#model_for`, `#reasoning_effort_for`, and `#model`
  # delegate there so call sites in the pipeline still read
  # `config.model_for(:narrate)` etc.

  # Closed whitelist for the narrative facts store's embedding model
  # selector (see Decision 37). The `adventure_narrative_facts.embedding`
  # column is fixed at `vector(1536)`, so models with native dim > 1536
  # need `dimensions: 1536` passed to OpenAI to truncate to our column
  # width — captured here as `dimensions_override` so the read/write
  # call sites don't have to duplicate that mapping.
  EMBEDDING_MODELS = [
    {
      'id' => 'text-embedding-3-small',
      'name' => 'text-embedding-3-small (default)',
      'native_dimensions' => 1536,
      'dimensions_override' => nil,
      'input_cost' => 0.02,
      'description' => 'Cheap, fast, 1536-d native. Good retrieval quality for the price.'
    },
    {
      'id' => 'text-embedding-3-large',
      'name' => 'text-embedding-3-large',
      'native_dimensions' => 3072,
      'dimensions_override' => 1536,
      'input_cost' => 0.13,
      'description' => 'Best OpenAI retrieval quality; native 3072-d truncated to 1536-d for our column. ~6.5× cost of -3-small.'
    },
    {
      'id' => 'text-embedding-ada-002',
      'name' => 'text-embedding-ada-002 (legacy)',
      'native_dimensions' => 1536,
      'dimensions_override' => nil,
      'input_cost' => 0.10,
      'description' => 'Previous generation; worse quality than -3-small at 5× the cost. Kept for compatibility only.'
    }
  ].freeze

  EMBEDDING_MODEL_IDS = EMBEDDING_MODELS.map { |m| m['id'] }.freeze
  EMBEDDING_MODEL_HINT = 'Model used to embed both stored facts (write path) and player intents (read path). Switching the model invalidates existing vectors — already-stored facts will retrieve poorly until re-embedded. Pick once and only change with a deliberate backfill plan.'

  WAIT_MESSAGES_DEFAULT = [
    'Sculpting nightmarish creatures from clay...',
    'Convincing the universe to exist...',
    'Teaching goblins to read...',
    'Populating taverns with suspicious characters...',
    'Rolling for initiative on your behalf...',
    'Brewing mysterious potions...',
    'Arguing with a dragon about property taxes...',
    'Consulting ancient tomes of forbidden knowledge...',
    'Hiring bards to compose your theme song...',
    'Placing traps in convenient locations...',
    "Negotiating with the dungeon's landlord...",
    'Convincing mimics to hold still...',
    'Calibrating the alignment of the stars...',
    'Sharpening every sword in the kingdom...',
    'Asking the oracle for directions...'
  ].freeze

  DEFAULTS = {
    'temperature' => 0.8,
    'pacing_words_min' => 40,
    'pacing_words_max' => 120,
    'danger_threshold' => 30,
    'action_queue' => 'progressive',
    'show_roll_dc' => true,
    'creature_creation_fallback' => 'ai',
    'instant_death' => true,
    'no_auto_hit_miss' => true,
    'terrain_speed_modifiers' => {
      'road' => 1.0, 'trail' => 0.75, 'urban' => 1.0, 'coast' => 0.75,
      'forest' => 0.5, 'swamp' => 0.5, 'desert' => 0.75, 'river' => 0.5,
      'mountain' => 0.25, 'underground' => 0.5
    },
    'wait_messages' => WAIT_MESSAGES_DEFAULT,
    'narrative_facts_top_k' => 8,
    'narrative_facts_active_window' => 20,
    'narrative_facts_embedding_model' => 'text-embedding-3-small',
    'stripe_grace_period_days' => 3
  }.freeze

  REASONING_EFFORTS = DmStepModelsConfig::REASONING_EFFORTS

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
    get('temperature').to_f
  end

  def pacing_words_min
    get('pacing_words_min').to_i
  end

  def pacing_words_max
    get('pacing_words_max').to_i
  end

  def danger_threshold
    get('danger_threshold').to_i
  end

  # Global default model — sourced from config/dm_step_models.yml.
  def model
    DmStepModelsConfig.default_model
  end

  # Resolved model for a pipeline step — sourced from
  # config/dm_step_models.yml (per-step override → default_model).
  def model_for(step)
    DmStepModelsConfig.model_for(step)
  end

  # Returns "minimal" | "low" | "medium" | "high" for the given step.
  # Sourced from config/dm_step_models.yml (per-step override →
  # default_reasoning_effort). AiClient drops the param when the
  # resolved model isn't a reasoning model, so non-reasoning overrides
  # stay safe.
  def reasoning_effort_for(step)
    DmStepModelsConfig.reasoning_effort_for(step)
  end

  def instant_death?
    get('instant_death') == true
  end

  def no_auto_hit_miss?
    get('no_auto_hit_miss') == true
  end

  def narrative_facts_top_k
    get('narrative_facts_top_k').to_i
  end

  def narrative_facts_active_window
    get('narrative_facts_active_window').to_i
  end

  def narrative_facts_embedding_model
    val = get('narrative_facts_embedding_model').to_s
    EMBEDDING_MODEL_IDS.include?(val) ? val : DEFAULTS['narrative_facts_embedding_model']
  end

  # Returns the `dimensions:` parameter to pass to OpenAI for the
  # currently-selected embedding model, or nil when the model's native
  # dim already matches our `vector(1536)` column. Call sites pass this
  # through to `AiClient#embeddings(dimensions:)`.
  def narrative_facts_embedding_dimensions
    entry = EMBEDDING_MODELS.find { |m| m['id'] == narrative_facts_embedding_model }
    entry && entry['dimensions_override']
  end

  def stripe_grace_period_days
    get('stripe_grace_period_days').to_i.clamp(1, 30)
  end
end
