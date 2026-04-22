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

    # Reads `key` from a Hash that may use either String or Symbol keys
    # (as raw JSON-parsed payloads from AI steps do) and coerces the
    # result to a String. Returns `""` when neither form is present.
    #
    # `key` must be a String — callers are deciding to treat the hash
    # as string-keyed-with-symbol-fallback, which is the convention for
    # model output in this repo.
    def indifferent_string(hash, key)
      value = hash[key] || hash[key.to_sym]
      value.is_a?(String) ? value : value.to_s
    end
  end
end
