# frozen_string_literal: true

module Encounters
  module Warmaster
    class EncounterInitializationRequest
      attr_reader :adventure, :encounter_entry, :sheet, :log, :config, :ai, :creatures_data

      def initialize(adventure:, encounter_entry:, sheet:, log:, config:, ai:, creatures_data: nil)
        @adventure = adventure
        @encounter_entry = encounter_entry
        @sheet = sheet
        @log = log
        @config = config
        @ai = ai
        @creatures_data = creatures_data
      end
    end
  end
end
