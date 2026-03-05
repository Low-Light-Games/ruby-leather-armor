# frozen_string_literal: true

# Static catalog of OpenAI chat-completion models loaded from
# config/openai_models.json. Edit that file to add new models
# or update pricing (Standard tier, $/1M tokens).
#
# Source: https://developers.openai.com/api/docs/pricing/
class OpenaiModelCatalog
  CATALOG_PATH = Rails.root.join("config/openai_models.json")

  EXCLUDE_KEYWORDS = %w[
    image tts transcribe realtime audio codex search-preview
    oss chat-latest sora deep-research computer-use
    embedding moderation whisper dall-e diarize babbage davinci
  ].freeze

  FALLBACK_TOKEN_BUDGETS = {
    "sanitize" => 400, "classify" => 300, "dm_query" => 400, "sequencer" => 300, "player_interpreter" => 300,
    "beacon" => 500, "mechanical_evaluation" => 600, "roll_qualifier" => 500, "sanity_checker" => 400, "sanity_checker_world" => 600,
    "verdict" => 700, "time_keeper" => 400, "narrate" => 900,
    "micro_context_update" => 900, "macro_narrative_update" => 600,
    "edge_pipeline" => 2500
  }.freeze

  def self.catalog
    @catalog ||= JSON.parse(CATALOG_PATH.read)
  rescue Errno::ENOENT, JSON::ParserError => e
    Rails.logger.error("[OpenaiModelCatalog] Failed to load #{CATALOG_PATH}: #{e.message}")
    {}
  end

  def self.reload!
    @catalog = nil
  end

  def self.chat_model?(model_id)
    return false unless model_id.match?(/\A(gpt-[345]|o[134])/)
    EXCLUDE_KEYWORDS.none? { |kw| model_id.include?(kw) }
  end

  def self.supports_temperature?(model_id)
    caps = catalog.dig(model_id, "capabilities")
    return true unless caps
    caps.fetch("supports_temperature", true)
  end

  def self.reasoning_model?(model_id)
    caps = catalog.dig(model_id, "capabilities")
    return false unless caps
    caps.fetch("reasoning_model", false)
  end

  def self.default_token_budgets(model_id)
    catalog.dig(model_id, "default_token_budgets") || FALLBACK_TOKEN_BUDGETS
  end

  def self.for_model(model_id)
    meta = catalog[model_id] || {}
    { "id" => model_id, "name" => meta["name"] || model_id,
      "description" => meta["description"],
      "input_cost" => meta["input_cost"], "output_cost" => meta["output_cost"],
      "reasoning_model" => reasoning_model?(model_id),
      "default_token_budgets" => default_token_budgets(model_id) }
  end

  def self.for_models(model_ids)
    model_ids.map { |id| for_model(id) }
  end
end
