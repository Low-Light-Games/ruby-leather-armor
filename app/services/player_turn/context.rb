# frozen_string_literal: true

module PlayerTurn
  class Context
    attr_reader :combined_seed, :player_action, :prior_outcomes, :death_type

    def initialize(combined_seed:, player_action:, prior_outcomes: nil, death_type: nil)
      @combined_seed  = combined_seed
      @player_action  = player_action
      @prior_outcomes = prior_outcomes
      @death_type     = death_type
    end
  end
end
