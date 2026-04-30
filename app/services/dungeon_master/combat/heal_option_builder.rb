# frozen_string_literal: true

module DungeonMaster
  module Combat
    # Sibling of BuffOptionBuilder — enumerates the player's known /
    # prepared spells with a healing effect they can self-cast in
    # combat. Returns one option per spell with the dice expression
    # the resolver will roll (caster-level bonus baked in, capped per
    # the spell's maxBonus when present).
    #
    # Self-cast only for now (target = the player). Healing an ally is
    # tracked in the same target-picker slice as Bless / Aid / Haste.
    module HealOptionBuilder
      SELF_HEAL_RANGES = %w[personal touch].freeze

      class << self
        # @param sheet [AdventureSheet]
        # @param adventure [Adventure]
        # @return [Array<Hash>]
        def call(sheet:, adventure:)
          return [] unless sheet

          return [] unless standard_action_available?(adventure)

          sheet.adventure_sheet_spells.includes(:spell_definition).filter_map do |entry|
            option_for_entry(entry, sheet)
          end
        end

        def option_for_entry(entry, sheet)
          spell = entry.spell_definition
          return nil unless spell

          effect = healing_effect_for(spell)
          return nil unless effect && self_heal_range?(spell) && friendly_save?(spell)

          build_option(spell, effect, sheet)
        end

        # @param sheet [AdventureSheet]
        # @param adventure [Adventure]
        # @param option_id [String] e.g. "spell:cure_light_wounds"
        # @return [Hash]
        def resolve_option_id!(sheet:, adventure:, option_id:)
          option = call(sheet: sheet, adventure: adventure).find { |o| o[:id] == option_id.to_s }
          return option if option

          raise DungeonMaster::CombatMechanicResolutionError.new(
            "unknown or unavailable heal option_id: #{option_id.inspect}",
            code: :unknown_heal_option
          )
        end

        private

        def standard_action_available?(adventure)
          ctx = adventure&.combat_context
          economy = ctx.is_a?(Hash) ? ctx['action_economy'] : nil
          return true unless economy.is_a?(Hash)

          econ = economy.deep_stringify_keys
          truthy?(econ['standard_available']) && !truthy?(econ['full_round_claimed'])
        end

        def truthy?(value)
          value == true || value.to_s == 'true'
        end

        def healing_effect_for(spell)
          Array(spell.effects).find { |e| e.is_a?(Hash) && e['type'].to_s == 'healing' }
        end

        def self_heal_range?(spell)
          range = spell.range.to_s.downcase.strip
          SELF_HEAL_RANGES.any? { |allowed| range == allowed || range.start_with?("#{allowed} ") }
        end

        def friendly_save?(spell)
          save = spell.saving_throw.to_s.downcase.strip
          save.empty? || save == 'none' || save.include?('(harmless)')
        end

        # Caster-level scaling: dice + min(caster_level * bonusPerLevel, maxBonus).
        # Cure Light Wounds: 1d8 + min(CL, 5). At L1 → 1d8+1.
        def build_option(spell, effect, sheet)
          base_dice  = effect['dice'].to_s
          per_level  = effect['bonusPerLevel'].to_i
          max_bonus  = effect['maxBonus']
          caster_lvl = sheet.level.to_i
          bonus      = per_level.positive? ? [caster_lvl * per_level, max_bonus.to_i].min : 0
          bonus      = caster_lvl * per_level if max_bonus.nil? && per_level.positive?
          dice       = bonus.positive? ? "#{base_dice}+#{bonus}" : base_dice

          {
            id: "spell:#{spell.id}",
            label: spell.name,
            source_type: 'spell',
            source_id: spell.id,
            dice: dice,
            summary: spell.summary,
            action_cost: 'standard'
          }.compact
        end
      end
    end
  end
end
