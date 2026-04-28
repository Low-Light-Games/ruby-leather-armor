# frozen_string_literal: true

module Combat
  module Narrator
    # Value object for the combat_narrator prompt template.
    class Context
      attr_reader :round, :npc_events, :adventure, :sheet

      def initialize(round:, npc_events:, adventure:, sheet:)
        @round = round
        @npc_events = Array(npc_events)
        @adventure = adventure
        @sheet = sheet
      end

      def player_name
        @sheet&.name.presence || 'the adventurer'
      end

      def location
        @adventure&.current_location&.name
      end

      def event_lines
        @npc_events.map { |e| event_line(e) }
      end

      private

      def event_line(event)
        symbolized = event.is_a?(Hash) ? event.deep_stringify_keys : {}
        case symbolized['kind']
        when 'npc_attack' then attack_line(symbolized)
        when 'npc_move'   then "- #{symbolized['creature_name']} moved toward you"
        when 'npc_flee'   then "- #{symbolized['creature_name']} retreated"
        when 'npc_skip'   then "- #{symbolized['creature_name']} held its action"
        else                   "- #{symbolized['creature_name']} #{symbolized['kind']}"
        end
      end

      def attack_line(event)
        outcome = event['outcome'] || {}
        verb = outcome['hit'] ? 'hit you' : 'missed you'
        damage_phrase = damage_phrase_for(outcome)
        dropped = outcome['target_dropped'] ? '; you fell unconscious' : ''
        label = event['attack_label'] || 'attack'
        "- #{event['creature_name']} (#{label}) #{verb}#{damage_phrase}#{dropped}"
      end

      def damage_phrase_for(outcome)
        damage = outcome['damage_total'].to_i
        return '' unless damage.positive?

        type = outcome['damage_type'].to_s
        type_phrase = type.empty? ? '' : " #{type}"
        " for #{damage}#{type_phrase} damage"
      end
    end
  end
end
