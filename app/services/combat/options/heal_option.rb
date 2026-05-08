# frozen_string_literal: true

module Combat
  module Options
    class HealOption
      def initialize(spell, sheet)
        @spell = spell
        @sheet = sheet
        @effect = Array(spell.effects).find { |e| e.is_a?(Hash) && e['type'].to_s == 'healing' } || {}
      end

      def to_h
        {
          id: "spell:#{@spell.id}",
          label: @spell.name,
          source_type: 'spell',
          source_id: @spell.id,
          dice: dice,
          summary: @spell.summary,
          action_cost: 'standard'
        }
      end

      private

      def dice
        base = @effect['dice'].to_s
        per_level = @effect['bonusPerLevel'].to_i
        return base unless per_level.positive?

        bonus = @sheet.level.to_i * per_level
        max = @effect['maxBonus']
        bonus = [bonus, max.to_i].min if max
        bonus.positive? ? "#{base}+#{bonus}" : base
      end
    end
  end
end
