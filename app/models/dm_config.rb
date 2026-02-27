class DmConfig < ApplicationRecord
  # Single-row configuration for the AI Dungeon Master.
  # Settings are stored as a JSON hash, making it easy to add new knobs
  # without migrations.
  #
  # Current settings:
  #   "verbose"                 => bool  (default false) — disables pacing constraints, lets DM write longer responses
  #   "temperature"             => float (default 0.8)   — creativity level for DM responses
  #   "pacing_words_min"        => int   (default 80)    — minimum word target per response
  #   "pacing_words_max"        => int   (default 150)   — maximum word target per response
  #   "sanitization_threshold"  => int   (default 50)    — danger score (0-100) above which input is rejected
  #   "classification_mode"     => str   (default "merged")     — "merged" or "parallel"
  #   "response_mode"           => str   (default "unified")    — "unified" or "sequential"
  #   "context_mode"            => str   (default "history")    — "history" or "contexts_only"
  #   "dm_mode"                 => str   (default "standard")   — "standard" or "light"

  DEFAULTS = {
    "verbose" => false,
    "temperature" => 0.8,
    "pacing_words_min" => 80,
    "pacing_words_max" => 150,
    "sanitization_threshold" => 30,
    "classification_mode" => "merged",
    "response_mode" => "unified",
    "context_mode" => "history",
    "dm_mode" => "standard"
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

  def classification_mode
    get("classification_mode") || "merged"
  end

  def classification_merged?
    classification_mode == "merged"
  end

  def response_mode
    get("response_mode") || "unified"
  end

  def response_sequential?
    response_mode == "sequential"
  end

  def context_mode
    get("context_mode") || "history"
  end

  def contexts_only?
    context_mode == "contexts_only"
  end

  def dm_mode
    get("dm_mode") || "standard"
  end

  def dm_mode_light?
    dm_mode == "light"
  end
end
