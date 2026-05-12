# frozen_string_literal: true

module PlayerTurn
  class EvaluationResult
    attr_reader :intention, :destination, :combat_transition,
                :target_actor_sheet_id,
                :consequences, :mechanical_summary
    attr_accessor :player_rolls

    def initialize(intention:, destination: nil,
                   combat_transition: nil, target_actor_sheet_id: nil,
                   player_rolls: [], consequences: [], mechanical_summary: '')
      @intention                = intention.to_s
      @destination              = destination.presence
      @combat_transition        = combat_transition.to_s.presence
      @target_actor_sheet_id = Coerce.actor_sheet_id(target_actor_sheet_id)
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
        target_actor_sheet_id: @target_actor_sheet_id,
      }.compact
    end
  end
end
