# frozen_string_literal: true

module Combat
  module Resolvers
    class HealPayload
      def initialize(option:, hp_before:, hp_after:, max_hp:, rolled:)
        @option = option
        @hp_before = hp_before
        @hp_after = hp_after
        @max_hp = max_hp
        @rolled = rolled
      end

      def to_h
        {
          kind: 'heal',
          spell_id: @option[:source_id],
          spell_name: @option[:label],
          dice: @option[:dice],
          rolled: @rolled,
          healed: healed,
          hp_before: @hp_before,
          hp_after: @hp_after,
          action_cost: @option[:action_cost],
          message: "#{@option[:label]} heals you for #{healed} HP (#{@hp_after}/#{@max_hp})."
        }
      end

      private

      def healed
        @hp_after - @hp_before
      end
    end
  end
end
