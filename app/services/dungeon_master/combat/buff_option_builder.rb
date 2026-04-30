# frozen_string_literal: true

module DungeonMaster
  module Combat
    # Sibling of AttackOptionBuilder — enumerates the player's known /
    # prepared spells the HUD can apply to the player as a self-buff.
    # Includes both personal-range spells (Shield, Longstrider, True
    # Strike, Mirror Image, Blur, etc.) and touch-range buffs the
    # player commonly self-casts (Mage Armor, Bull's Strength, Aid).
    # Healing spells, harmful saves, and AOE / ranged buffs that need
    # target picking (Bless, Haste, Cure on an ally) are excluded —
    # those land in the next slice.
    module BuffOptionBuilder
      SELF_BUFF_RANGES = %w[personal touch].freeze
      BUFF_EFFECT_TYPES = %w[ac_bonus attack_bonus save_bonus skill_bonus
                             ability_bonus immunity special damage_resistance
                             concealment].freeze
      DAMAGE_EFFECT_TYPES = %w[damage healing].freeze

      class << self
        # @param sheet [AdventureSheet]
        # @param adventure [Adventure]
        # @return [Array<Hash>]
        def call(sheet:, adventure:)
          return [] unless sheet

          return [] unless standard_action_available?(adventure)

          sheet.adventure_sheet_spells.includes(:spell_definition).filter_map do |entry|
            spell = entry.spell_definition
            next unless spell

            next unless self_buff?(spell)

            build_option(spell)
          end
        end

        # @param sheet [AdventureSheet]
        # @param adventure [Adventure]
        # @param option_id [String] e.g. "spell:shield"
        # @return [Hash]
        def resolve_option_id!(sheet:, adventure:, option_id:)
          option = call(sheet: sheet, adventure: adventure).find { |o| o[:id] == option_id.to_s }
          return option if option

          raise DungeonMaster::CombatMechanicResolutionError.new(
            "unknown or unavailable buff option_id: #{option_id.inspect}",
            code: :unknown_buff_option
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

        def self_buff?(spell)
          return false unless self_buff_range?(spell)

          return false unless self_buff_save?(spell)

          return false if damage_or_healing_effect?(spell)

          buff_effects_for(spell).any?
        end

        def self_buff_range?(spell)
          range = spell.range.to_s.downcase.strip
          SELF_BUFF_RANGES.any? { |allowed| range == allowed || range.start_with?("#{allowed} ") }
        end

        # `none` (Shield, Longstrider, True Strike) or `... (harmless)`
        # (Mage Armor, Bull's Strength). Anything else means the spell
        # forces a save on the target — not a self-buff.
        def self_buff_save?(spell)
          save = spell.saving_throw.to_s.downcase.strip
          save.empty? || save == 'none' || save.include?('(harmless)')
        end

        def damage_or_healing_effect?(spell)
          Array(spell.effects).any? { |e| e.is_a?(Hash) && DAMAGE_EFFECT_TYPES.include?(e['type'].to_s) }
        end

        def buff_effects_for(spell)
          Array(spell.effects).select { |e| e.is_a?(Hash) && BUFF_EFFECT_TYPES.include?(e['type'].to_s) }
        end

        def build_option(spell)
          {
            id: "spell:#{spell.id}",
            label: spell.name,
            source_type: 'spell',
            source_id: spell.id,
            duration: spell.duration,
            summary: spell.summary,
            action_cost: 'standard'
          }.compact
        end
      end
    end
  end
end
