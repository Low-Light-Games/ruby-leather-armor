# frozen_string_literal: true

module Combat
  module Resolvers
    # Wire payload returned to the HUD when a buff cast resolves.
    class BuffPayload
      def initialize(option:, spell:)
        @option = option
        @spell = spell
      end

      def to_h
        {
          kind: 'buff',
          spell_id: @spell.id,
          spell_name: @spell.name,
          duration: @spell.duration,
          summary: @spell.summary,
          action_cost: @option[:action_cost],
          message: "#{@spell.name} active — #{@spell.summary}"
        }
      end
    end
  end
end
