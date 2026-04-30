# frozen_string_literal: true

module DungeonMaster
  module Combat
    # HUD payload for one buff button. Wraps a SpellDefinition in the
    # exact { id, label, source_type, source_id, duration, summary,
    # action_cost } shape the combat_action/options endpoint emits.
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
