# frozen_string_literal: true

module Encounters
  module Warmaster
    class NamesPreparationRequest
      attr_reader :adventure, :combatant_names, :count, :sheet, :log, :config, :ai

      def initialize(adventure:, combatant_names:, sheet:, log:, config:, ai:, count: nil)
        @adventure = adventure
        @combatant_names = combatant_names
        @count = count
        @sheet = sheet
        @log = log
        @config = config
        @ai = ai
      end
    end
  end
end
