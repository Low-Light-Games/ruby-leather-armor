class DmConfig < ApplicationRecord
  # Single-row configuration for the AI Dungeon Master.
  # Settings are stored as a JSON hash, making it easy to add new knobs
  # without migrations.
  #
  # Current settings:
  #   "verbose"          => bool  (default false) — disables pacing constraints, lets DM write longer responses
  #   "temperature"      => float (default 0.8)   — creativity level for DM responses
  #   "pacing_words_min" => int   (default 80)    — minimum word target per response
  #   "pacing_words_max" => int   (default 150)   — maximum word target per response

  DEFAULTS = {
    "verbose" => false,
    "temperature" => 0.8,
    "pacing_words_min" => 80,
    "pacing_words_max" => 150
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
end
