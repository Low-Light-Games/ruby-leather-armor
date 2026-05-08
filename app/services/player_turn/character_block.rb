# frozen_string_literal: true

module PlayerTurn
  module CharacterBlock
    module_function

    def full(sheet)
      raise ArgumentError, "CharacterBlock requires a sheet" unless sheet

      Presenters::AdventureSheetPromptPresenter.new(sheet).full
    end

    def creature_stats_for(adventure)
      Presenters::CreatureSheetPromptPresenter.stats_lines_for_adventure(adventure)
    end
  end
end
