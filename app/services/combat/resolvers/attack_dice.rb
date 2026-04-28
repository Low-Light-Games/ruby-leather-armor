# frozen_string_literal: true

module Combat
  module Resolvers
    # Dice + ability-bonus helpers for the player attack flow. Mixed in
    # by Combat::Resolvers::Attack to keep that module under the
    # Cursor module-length cap. Reads @sheet, @submitted_dice from the
    # includer.
    module AttackDice
      private

      def damage_ability_bonus(option)
        return 0 if option[:source_type].to_s == 'spell'

        return 0 if ranged_mode?(option[:attack_mode])

        mods = (@sheet.derived_stats || {})['mods'] || {}
        mods['strength'].to_i
      end

      def roll_player_attack(attack_bonus, defense_dc)
        natural = if @submitted_dice
                    validate_natural!(@submitted_dice[:attack_natural], 1..20, 'attack_natural')
                  else
                    DungeonMaster::Rolls::CombatDice.roll_d20
                  end
        total = natural + attack_bonus
        hit = (total >= defense_dc || natural == 20) && natural != 1
        { natural: natural, total: total, hit: hit }
      end

      def roll_player_damage(option, hit)
        return { natural: nil, total: nil } unless hit

        ability = damage_ability_bonus(option)
        base = if @submitted_dice
                 validate_natural!(@submitted_dice[:damage_natural], 1..1000, 'damage_natural')
               else
                 DungeonMaster::Rolls::CombatDice.roll_damage_expression(option[:damage].to_s)
               end
        { natural: base, total: [base + ability, 1].max }
      end

      def validate_natural!(value, range, label)
        n = value.to_i
        unless range.cover?(n)
          raise Combat::ResolverError.new("invalid #{label}: #{value.inspect}",
                                          code: :invalid_dice_submission)
        end

        n
      end

      def ranged_mode?(attack_mode)
        attack_mode.to_s.start_with?('ranged')
      end
    end
  end
end
