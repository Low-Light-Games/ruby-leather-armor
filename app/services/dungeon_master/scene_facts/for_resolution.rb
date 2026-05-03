# frozen_string_literal: true

module DungeonMaster
  module SceneFacts
    class ForResolution
      def self.call(adventure:, intent_text:, ai:, log:, limit: nil)
        new(adventure: adventure, intent_text: intent_text,
            ai: ai, log: log, limit: limit).call
      end

      def initialize(adventure:, intent_text:, ai:, log:, limit: nil)
        @adventure   = adventure
        @intent_text = intent_text.to_s
        @ai          = ai
        @log         = log
        @limit       = limit
      end

      def call
        Lore::FactsLookup.call(
          adventure:  @adventure,
          ai:         @ai,
          log:        @log,
          query_text: composed_query_text,
          limit:      @limit,
        )
      end

      private

      def composed_query_text
        parts = [@intent_text, current_location_name, *active_combat_participant_names]
        parts.compact.map(&:strip).reject(&:empty?).join(" ")
      end

      def current_location_name
        @adventure.current_location&.name
      end

      def active_combat_participant_names
        return [] unless combat_state.active?

        combat_state.participant_names
      end

      def combat_state
        @combat_state ||= Adventures::CombatState.from_adventure(@adventure)
      end
    end
  end
end
