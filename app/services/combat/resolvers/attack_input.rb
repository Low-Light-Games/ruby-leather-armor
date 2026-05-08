# frozen_string_literal: true

module Combat
  module Resolvers
    # @param option [Hash] resolved attack option (id/label/damage/...)
    # @param target [Array<(CreatureSheet, String)>] creature + display name
    # @param attack_bonus [Integer] post-flanking attack bonus
    # @param defense_dc [Integer] post-cover defense DC
    # @param situational [Combat::Resolvers::SituationalModifiers]
    class AttackInput
      attr_reader :option, :target, :attack_bonus, :defense_dc, :situational

      def initialize(option:, target:, attack_bonus:, defense_dc:, situational:)
        @option = option
        @target = target
        @attack_bonus = attack_bonus
        @defense_dc = defense_dc
        @situational = situational
      end
    end
  end
end
