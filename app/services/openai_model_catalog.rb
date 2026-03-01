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

  def self.reload!
    @catalog = nil
  end

  def self.chat_model?(model_id)
    return false unless model_id.match?(/\A(gpt-[345]|o[134])/)
    EXCLUDE_KEYWORDS.none? { |kw| model_id.include?(kw) }
  end

  def self.for_model(model_id)
    meta = catalog[model_id] || {}
    { "id" => model_id, "name" => meta["name"] || model_id,
      "description" => meta["description"],
      "input_cost" => meta["input_cost"], "output_cost" => meta["output_cost"] }
  end

  def self.for_models(model_ids)
    model_ids.map { |id| for_model(id) }
  end
end
