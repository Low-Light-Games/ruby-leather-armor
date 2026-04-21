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

  def self.catalog
    @catalog ||= JSON.parse(CATALOG_PATH.read)
  rescue Errno::ENOENT, JSON::ParserError => e
    Rails.logger.error("[OpenaiModelCatalog] Failed to load #{CATALOG_PATH}: #{e.message}")
    {}
  end

  # OpenAI API responses return pinned versioned model IDs (e.g. "gpt-4o-mini-2024-07-18")
  # even when the caller requested the base alias ("gpt-4o-mini"). The catalog is keyed
  # by alias, so strip the date suffix before any lookup.
  def self.normalize(model_id)
    model_id.to_s.sub(/-\d{4}-\d{2}-\d{2}(-preview)?$/, "")
  end

  def self.reload!
    @catalog = nil
  end

  def self.chat_model?(model_id)
    return false unless model_id.match?(/\A(gpt-[345]|o[134])/)

    EXCLUDE_KEYWORDS.none? { |kw| model_id.include?(kw) }
  end

  def self.supports_temperature?(model_id)
    caps = catalog.dig(normalize(model_id), "capabilities")
    return true unless caps

    caps.fetch("supports_temperature", true)
  end

  def self.reasoning_model?(model_id)
    caps = catalog.dig(normalize(model_id), "capabilities")
    return false unless caps

    caps.fetch("reasoning_model", false)
  end

  def self.for_model(model_id)
    meta = catalog[normalize(model_id)] || {}
    { "id" => model_id, "name" => meta["name"] || model_id,
      "description" => meta["description"],
      "input_cost" => meta["input_cost"], "output_cost" => meta["output_cost"],
      "reasoning_model" => reasoning_model?(model_id) }
  end

  def self.for_models(model_ids)
    model_ids.map { |id| for_model(id) }
  end
end
