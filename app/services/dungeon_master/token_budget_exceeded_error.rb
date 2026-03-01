# frozen_string_literal: true

module DungeonMaster
  class TokenBudgetExceededError < AiError
    attr_reader :step_name, :budget

    def initialize(step_name:, budget:)
      @step_name = step_name
      @budget = budget
      super(
        "Token budget exceeded on '#{step_name}' step (budget: #{budget}). " \
        "Increase the budget in DM Config > Token Budgets."
      )
    end
  end
end
