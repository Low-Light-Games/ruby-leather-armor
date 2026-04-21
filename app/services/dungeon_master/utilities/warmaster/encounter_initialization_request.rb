# frozen_string_literal: true

module DungeonMaster
  module Utilities
    module Warmaster
      class EncounterInitializationRequest
        attr_reader :adventure, :encounter_entry, :sheet, :log, :config, :ai, :creatures_data, :scene_enemy_names

        def initialize(adventure:, encounter_entry:, sheet:, log:, config:, ai:, creatures_data: nil, scene_enemy_names: nil)
          @adventure = adventure
          @encounter_entry = encounter_entry
          @sheet = sheet
          @log = log
          @config = config
          @ai = ai
          @creatures_data = creatures_data
          @scene_enemy_names = scene_enemy_names
        end
      end
    end
  end
end
