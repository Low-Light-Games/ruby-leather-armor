# frozen_string_literal: true

module DungeonMaster
  module Steps
    module GameMaster
      class PendingToolsResult
        attr_reader :lead_narrative, :tool_calls, :intent_text

        def initialize(lead_narrative:, tool_calls:, intent_text:)
          @lead_narrative = lead_narrative
          @tool_calls = tool_calls
          @intent_text = intent_text
        end

        def to_h
          {
            action: :game_master_pending_tools,
            lead_narrative: @lead_narrative,
            tool_calls: @tool_calls,
            intent_text: @intent_text
          }
        end
      end
    end
  end
end
