# frozen_string_literal: true

module Combat
  module Options
    class BuffOption
      def initialize(spell)
        @spell = spell
      end

      def to_h
        {
          id: "spell:#{@spell.id}",
          label: @spell.name,
          source_type: 'spell',
          source_id: @spell.id,
          duration: @spell.duration,
          summary: @spell.summary,
          action_cost: 'standard'
        }
      end
    end
  end
end
