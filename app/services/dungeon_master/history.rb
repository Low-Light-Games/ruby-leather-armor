# frozen_string_literal: true

module DungeonMaster
  # Builds the conversation history array that gets sent to the AI
  # so it has context on previous exchanges in this adventure.
  module History
    CONTEXT_WINDOW = 20

    # Converts recent AdventureMessages into the OpenAI messages format.
    #
    # @param adventure [Adventure]
    # @return [Array<Hash>]  each element has :role and :content
    def self.build(adventure)
      adventure.adventure_messages.chronological.last(CONTEXT_WINDOW).map do |msg|
        role = case msg.role
               when "player" then "user"
               when "dm"     then "assistant"
               when "system" then "user" # System messages presented as user context
               end
        { role: role, content: msg.content }
      end
    end
  end
end
