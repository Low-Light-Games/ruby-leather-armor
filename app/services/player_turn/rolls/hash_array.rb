# frozen_string_literal: true

module PlayerTurn
  module Rolls
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
