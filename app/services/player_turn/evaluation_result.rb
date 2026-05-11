# frozen_string_literal: true

module PlayerTurn
  # Output of a RollRequest (or CombatRollRequest) evaluation step.
  #
  # `target_creature_sheet_id` is an optional integer ID pointing at one
  # row of the upstream cast roster. `combat_transition` is an
  # independent signal — a hostile target can be observed, lied to,
  # intimidated, or avoided, and a friendly target can be attacked, so
  # combat-start and target identity stay orthogonal.
  class EvaluationResult
    attr_reader :intention, :destination, :combat_transition,
                :target_creature_sheet_id,
                :consequences, :mechanical_summary
    attr_accessor :player_rolls

    def initialize(intention:, destination: nil,
                   combat_transition: nil, target_creature_sheet_id: nil,
                   player_rolls: [], consequences: [], mechanical_summary: '')
      @intention                = intention.to_s
      @destination              = destination.presence
      @combat_transition        = combat_transition.to_s.presence
      @target_creature_sheet_id = coerce_target_id(target_creature_sheet_id)
      @player_rolls             = Array(player_rolls)
      @consequences             = Array(consequences).map(&:to_s).reject(&:blank?)
      @mechanical_summary       = mechanical_summary.to_s
    end

    def combat_starting?
      @combat_transition.present? &&
        Combat::Transitions.start?(@combat_transition)
    end

    def to_intent_hash
      {
        intention:                @intention,
        destination:              @destination,
        transition:               @combat_transition,
        target_creature_sheet_id: @target_creature_sheet_id,
      }.compact
    end

    private

    def coerce_target_id(raw)
      return nil if raw.nil? || raw == ""

      Integer(raw, exception: false)
    end
  end
end
