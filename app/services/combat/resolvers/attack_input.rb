# frozen_string_literal: true

module Combat
  module Resolvers
    # Bundled record threaded through Combat::Resolvers::Attack —
    # everything the dice + payload helpers need from the lookup phase
    # so each helper signature stays under the parameter-list cap.
    #
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
