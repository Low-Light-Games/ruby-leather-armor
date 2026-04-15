# frozen_string_literal: true

module DungeonMaster
  module AdventurePlay
    # Persisted metadata on initiative_request messages when the pipeline pauses for a roll.
    module InitiativeRequestMetadata
      module_function

      def for_awaiting_initiative(result)
        {
          creature_data: result[:creature_data],
          intent: result[:intent],
          mutations: result[:mutations],
          pending_opening_merged: result[:merged]&.deep_stringify_keys,
          remaining_actions: result[:remaining_actions]
        }
      end
    end
  end
end
