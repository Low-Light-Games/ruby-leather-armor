# frozen_string_literal: true

module Narration
  module PhaseResults
    module_function

    class Narrated
      def initialize(narrative:, adventure_complete:, extras: {})
        @narrative = narrative
        @adventure_complete = adventure_complete
        @extras = extras || {}
      end

      def to_h
        {
          action: :narrated,
          narrative: @narrative,
          adventure_complete: @adventure_complete,
        }.merge(@extras)
      end
    end

    class AwaitingInitiative
      def initialize(intent:, creature_data:, mutations:, extras: {})
        @intent = intent
        @creature_data = creature_data
        @mutations = mutations
        @extras = extras || {}
      end

      def to_h
        {
          action: :awaiting_initiative,
          intent: @intent,
          creature_data: @creature_data,
          mutations: @mutations,
        }.merge(@extras)
      end
    end

    def narrated(narrative:, adventure_complete:, extras: {})
      Narrated.new(narrative: narrative, adventure_complete: adventure_complete, extras: extras)
    end

    def awaiting_initiative(intent:, creature_data:, mutations:, extras: {})
      AwaitingInitiative.new(
        intent: intent,
        creature_data: creature_data,
        mutations: mutations,
        extras: extras,
      )
    end
  end
end
