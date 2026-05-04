# frozen_string_literal: true

module DungeonMaster
  # Output of RollRequest / CombatRollRequest. Carries the action-shape
  # signals downstream code consumes — destination, combat transition +
  # combatants, optional roll spec, mechanical summary. The `affected_*`
  # micro-context keys were retired with the rest of the per-domain
  # routing.
  class EvaluationResult
    attr_reader :intention, :destination, :combat_transition, :combat_combatants,
                :consequences, :mechanical_summary
    attr_accessor :player_rolls

    def initialize(intention:, destination: nil, macro_significant: false,
                   combat_transition: nil, combat_combatants: [], combat_ending: false,
                   player_rolls: [], consequences: [], mechanical_summary: '')
      @intention = intention.to_s
      @destination = destination.presence
      @macro_significant = macro_significant == true
      @combat_transition = combat_transition.to_s.presence
      @combat_combatants = Array(combat_combatants).map(&:to_s).reject(&:blank?)
      @combat_ending = combat_ending == true
      @player_rolls = Array(player_rolls)
      @consequences = Array(consequences).map(&:to_s).reject(&:blank?)
      @mechanical_summary = mechanical_summary.to_s
    end

    def macro_significant? = @macro_significant
    def combat_ending? = @combat_ending

    def combat_starting?
      @combat_transition.present? &&
        DungeonMaster::CombatTransitions.start?(@combat_transition)
    end

    def to_intent_hash
      {
        intention: @intention,
        destination: @destination,
        transition: @combat_transition,
        combat_combatants: @combat_combatants,
        macro_significant: @macro_significant,
        combat_ending: @combat_ending
      }
    end
  end
end
