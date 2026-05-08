# frozen_string_literal: true

module PlayerTurn
  module Rolls
    module SituationalModifiers
      module_function

      # @param raw [Array, nil]
      # @return [Array<Hash>] symbolized hash entries; non-hash entries dropped
      def normalize(raw)
        Array(raw).filter_map do |entry|
          entry.deep_symbolize_keys if entry.is_a?(Hash)
        end
      end
    end
  end
end
