# frozen_string_literal: true

module DungeonMaster
  module Utilities
    module Warmaster
      class CombatInitializationRequest
        attr_reader :adventure, :player_sheet, :creature_data, :player_initiative

        def initialize(adventure:, player_sheet:, creature_data:, player_initiative:)
          @adventure = adventure
          @player_sheet = player_sheet
          @creature_data = creature_data
          @player_initiative = player_initiative
        end
      end
    end
  end
end
