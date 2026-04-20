# frozen_string_literal: true

module DungeonMaster
  module FlowResults
    module_function

    class AwaitingRolls
      def initialize(intent:, merged:, remaining_actions: nil)
        @intent = intent
        @merged = merged
        @remaining_actions = remaining_actions
      end

      def to_h
        payload = { status: :awaiting_rolls, intent: @intent, merged: @merged }
        payload[:remaining_actions] = @remaining_actions if @remaining_actions
        payload
      end
    end

    class AwaitingInitiative
      def initialize(intent:, creature_data:, mutations:, opener_outcome: nil, pending_opening_merged: nil, remaining_actions: nil)
        @intent = intent
        @creature_data = creature_data
        @mutations = mutations
        @opener_outcome = opener_outcome
        @pending_opening_merged = pending_opening_merged
        @remaining_actions = remaining_actions
      end

      def to_h
        payload = {
          status: :awaiting_initiative,
          intent: @intent,
          creature_data: @creature_data,
          mutations: @mutations
        }
        payload[:opener_outcome] = @opener_outcome if @opener_outcome
        payload[:pending_opening_merged] = @pending_opening_merged if @pending_opening_merged
        payload[:remaining_actions] = @remaining_actions if @remaining_actions
        payload
      end
    end

    class Rejected
      def initialize(intent:, reason:, dm_message: nil)
        @intent = intent
        @reason = reason
        @dm_message = dm_message
      end

      def to_h
        payload = { status: :rejected, intent: @intent, reason: @reason }
        payload[:dm_message] = @dm_message if @dm_message
        payload
      end
    end

    class Encounter
      def initialize(intent:, mutations:, time_result:)
        @intent = intent
        @mutations = mutations
        @time_result = time_result
      end

      def to_h
        { status: :encounter, intent: @intent, mutations: @mutations, time_result: @time_result }
      end
    end

    class SocialScene
      def initialize(intent:)
        @intent = intent
      end

      def to_h
        { status: :social_scene, intent: @intent }
      end
    end

    def awaiting_rolls(intent:, merged:, remaining_actions: nil)
      AwaitingRolls.new(intent: intent, merged: merged, remaining_actions: remaining_actions)
    end

    def awaiting_initiative(intent:, creature_data:, mutations:, opener_outcome: nil, pending_opening_merged: nil, remaining_actions: nil)
      AwaitingInitiative.new(
        intent: intent,
        creature_data: creature_data,
        mutations: mutations,
        opener_outcome: opener_outcome,
        pending_opening_merged: pending_opening_merged,
        remaining_actions: remaining_actions
      )
    end

    def rejected(intent:, reason:, dm_message: nil)
      Rejected.new(intent: intent, reason: reason, dm_message: dm_message)
    end

    def encounter(intent:, mutations:, time_result:)
      Encounter.new(intent: intent, mutations: mutations, time_result: time_result)
    end

    def social_scene(intent:)
      SocialScene.new(intent: intent)
    end
  end
end
