# frozen_string_literal: true

module DungeonMaster
  module TextNormalizer
    module_function

    def strip(text)
      text.to_s.strip
    end

    def normalized_key(text)
      strip(text).downcase
    end

    def present_or(text, fallback)
      strip(text).presence || fallback
    end

    def singular_identifier(text)
      normalized_key(text).singularize.gsub(/\s+/, "_")
    end

    def class_slug_tokens(text)
      normalized_key(text).split(%r{[/\s]+})
    end

    # TODO: Improve readability — symbol/string indifference should be enforced at the AI-response parse boundary via a typed wrapper, not handed off to every caller.
    def indifferent_string(hash, key)
      value = hash[key] || hash[key.to_sym]
      value.is_a?(String) ? value : value.to_s
    end
  end
end
