# frozen_string_literal: true

module PlayerTurn
  module Steps
    module SocialMaster
      class Inputs
        attr_reader :narrative, :known_npc_names

        def initialize(narrative:, known_npc_names: [])
          @narrative       = narrative
          @known_npc_names = known_npc_names
          freeze
        end
      end
    end
  end
end
