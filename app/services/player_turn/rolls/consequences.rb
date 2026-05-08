# frozen_string_literal: true

module PlayerTurn
  module Rolls
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
