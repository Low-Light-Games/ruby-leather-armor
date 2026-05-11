# frozen_string_literal: true

module Combat
  module Resolvers
    class PendingDiceRequest
      attr_reader :inputs, :creature, :target_name, :damage_ability_bonus

      # @param inputs [Combat::Resolvers::AttackInput] resolved option +
      # @param creature [CreatureSheet] the chosen target
      # @param target_name [String] display label for the prompt
      # @param damage_ability_bonus [Integer] STR/DEX/etc bonus the
      def initialize(inputs:, creature:, target_name:, damage_ability_bonus:)
        @inputs = inputs
        @creature = creature
        @target_name = target_name
        @damage_ability_bonus = damage_ability_bonus
      end

      def to_h
        option = inputs.option
        situational = inputs.situational
        {
          kind: 'attack',
          attack_option_id: option[:id].to_s,
          attack_label: option[:label].to_s,
          target_name: target_name,
          target_creature_sheet_id: creature.id,
          attack_bonus: inputs.attack_bonus,
          defense_dc: inputs.defense_dc,
          defense_kind: option[:defense_kind],
          damage_expression: option[:damage],
          damage_type: option[:damage_type],
          damage_ability_bonus: damage_ability_bonus,
          flanking: situational.flanking,
          flanking_bonus: situational.flanking_bonus,
          cover_bonus: situational.cover_bonus
        }
      end
    end
  end
end
