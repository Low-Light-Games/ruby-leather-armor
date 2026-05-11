# frozen_string_literal: true

module Combat
  module Resolvers
    class EndTurnSummary
      KIND = 'end_turn'

      # @param next_round [Integer]
      # @param npc_events [Array<Hash>] NpcTurnEvent#to_h hashes
      def initialize(next_round:, npc_events:)
        @next_round = next_round
        @npc_events = npc_events
      end

      def to_h
        {
          kind: KIND,
          round_advanced_to: @next_round,
          npc_events: @npc_events,
          message: human_message
        }
      end

      private

      def human_message
        "Turn ended. #{@npc_events.length} NPC action(s), #{npc_hits} hit(s). Round #{@next_round} begins."
      end

      def npc_hits
        @npc_events.count do |e|
          e[:kind] == NpcTurnEvent::KIND_ATTACK && e.dig(:outcome, 'hit') == true
        end
      end
    end
  end
end
