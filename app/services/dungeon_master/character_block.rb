# frozen_string_literal: true

module DungeonMaster
  # Facade for prompt-safe character/creature text. Formatting lives in Presenters.
  module CharacterBlock
    module_function

    def load_sheet(adventure)
      AdventureSheet.for_adventure(adventure)
    end

    def full(sheet)
      raise ArgumentError, "CharacterBlock requires a sheet" unless sheet

      Presenters::AdventureSheetPromptPresenter.new(sheet).full
    end

    def creature_stats_for(adventure)
      Presenters::CreatureSheetPromptPresenter.stats_lines_for_adventure(adventure)
    end
  end
end
