# frozen_string_literal: true

module DungeonMaster
  module Rolls
    # Generic safety net for AI-emitted JSON arrays the pipeline persists
    # and later resumes via deep_symbolize_keys. Plain strings (or any
    # non-Hash entry) used to crash the resume path with "undefined
    # method `deep_symbolize_keys' for an instance of String"; this
    # filter_maps to hashes only.
    module HashArray
      module_function

      # @param raw [Array, nil]
      # @return [Array<Hash>]
      def symbolize_strict(raw)
        Array(raw).filter_map { |entry| entry.deep_symbolize_keys if entry.is_a?(Hash) }
      end
    end
  end
end
