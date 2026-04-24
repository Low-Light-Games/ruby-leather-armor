# frozen_string_literal: true

module CharacterStats
  # JSON/JSONB array columns on sheets: nil → [], non-Array → [] (no coercion of single values).
  module PersistedJsonArray
    module_function

    def list(value)
      return [] if value.nil?

      return value if value.is_a?(Array)

      []
    end
  end
end
