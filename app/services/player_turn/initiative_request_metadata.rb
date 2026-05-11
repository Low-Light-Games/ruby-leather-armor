# frozen_string_literal: true

module PlayerTurn
  module InitiativeRequestMetadata
    module_function

    def for_awaiting_initiative(result)
      {
        creature_data: result[:creature_data],
        intent: result[:intent],
        mutations: result[:mutations],
        opener_outcome: result[:opener_outcome],
        pending_opening_merged: (result[:pending_opening_merged] || result[:merged])&.deep_stringify_keys,
        remaining_actions: result[:remaining_actions]
      }
    end
  end
end
