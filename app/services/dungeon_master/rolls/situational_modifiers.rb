# frozen_string_literal: true

module DungeonMaster
  module Rolls
    # Normalizes the situational_modifiers array the AI emits on a roll
    # request. Expected entry shape is { source: String, modifier:
    # Integer }, but the model occasionally returns plain strings or
    # other shapes — drop those instead of crashing the whole turn on
    # `deep_symbolize_keys`.
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
