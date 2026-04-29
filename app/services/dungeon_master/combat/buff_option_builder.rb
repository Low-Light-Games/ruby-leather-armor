# frozen_string_literal: true

module DungeonMaster
  module Combat
    # Sibling of AttackOptionBuilder — enumerates the player's known /
    # prepared spells whose effects are self-buffs (no damage roll, no
    # save against the player, personal range). The HUD renders one
    # button per option below the attack list.
    #
    # First slice covers personal-range spells only (Shield, Mage Armor,
    # Longstrider, True Strike, Mirror Image, Blur, Expeditious Retreat,
    # Prot. from Evil, etc.). Touch / close ranged buffs (Bless, Aid,
    # Cure Light Wounds) need target selection and are tracked
    # separately.
    module BuffOptionBuilder
      BUFF_EFFECT_TYPES = %w[ac_bonus attack_bonus save_bonus skill_bonus
                             ability_bonus immunity special damage_resistance
                             concealment].freeze

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
          return false unless spell.range.to_s.downcase.strip == 'personal'

          return false if damage_effect?(spell)

          buff_effects_for(spell).any?
        end

        def damage_effect?(spell)
          Array(spell.effects).any? { |e| e.is_a?(Hash) && e['type'].to_s == 'damage' }
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
