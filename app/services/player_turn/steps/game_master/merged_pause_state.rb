# frozen_string_literal: true

module PlayerTurn
  module Steps
    module GameMaster
      class MergedPauseState
        def initialize(request_roll_result:)
          @request_roll_result = request_roll_result
        end

        def to_h
          {
            player_rolls: [@request_roll_result.to_h],
            npc_actions: [],
            consequences: [],
            mechanical_summaries: [@request_roll_result.mechanical_summary].reject(&:blank?),
            roll_chain: nil
          }
        end
      end
    end
  end
end
