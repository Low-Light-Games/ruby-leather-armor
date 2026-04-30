# frozen_string_literal: true

module DungeonMaster
  module Combat
    # HUD payload for one healing button. Wraps a SpellDefinition + the
    # caster's level into the dice expression the resolver will roll
    # (caster-level bonus baked in, capped at effect.maxBonus).
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

      # Cure Light Wounds at L1 → "1d8+1"; capped at effect.maxBonus.
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
