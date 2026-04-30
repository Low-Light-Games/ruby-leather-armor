# frozen_string_literal: true

module DungeonMaster
  module Rolls
    # Normalizes the consequences array — entries can arrive as either
    # `{ description: String }` hashes (the canonical shape every prompt
    # example pins) or as bare strings the model occasionally emits
    # anyway. Strings get wrapped as `{ description: str }`; non-hash
    # non-string entries are dropped instead of crashing the
    # `deep_symbolize_keys` chain on resume.
    module Consequences
      module_function

      # @param raw [Array, nil]
      # @return [Array<Hash>]
      def normalize(raw)
        Array(raw).filter_map do |entry|
          case entry
          when Hash   then entry.deep_symbolize_keys
          when String then { description: entry }
          end
        end
      end
    end
  end
end
