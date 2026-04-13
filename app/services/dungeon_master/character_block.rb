# frozen_string_literal: true

module DungeonMaster
  # Facade for prompt-safe character/creature text. Formatting lives in Presenters.
  module CharacterBlock
    module_function

    def load_sheet(adventure)
      AdventureSheet.for_adventure(adventure)
    end

    def for(sheet, category: nil)
      raise ArgumentError, "CharacterBlock requires a sheet" unless sheet

      Presenters::AdventureSheetPromptPresenter.new(sheet).for_category(category)
    end

    def identity(sheet)
      raise ArgumentError, "CharacterBlock requires a sheet" unless sheet

      Presenters::AdventureSheetPromptPresenter.new(sheet).identity
    end

    def full(sheet)
      raise ArgumentError, "CharacterBlock requires a sheet" unless sheet

      Presenters::AdventureSheetPromptPresenter.new(sheet).full
    end

    def social(sheet)
      raise ArgumentError, "CharacterBlock requires a sheet" unless sheet

      Presenters::AdventureSheetPromptPresenter.new(sheet).social
    end

    def traversal(sheet)
      raise ArgumentError, "CharacterBlock requires a sheet" unless sheet

      Presenters::AdventureSheetPromptPresenter.new(sheet).traversal
    end

    def creature_stats_for(adventure)
      Presenters::CreatureSheetPromptPresenter.stats_lines_for_adventure(adventure)
    end

    def creature_npc_action_prompt(creature_sheet)
      Presenters::CreatureSheetPromptPresenter.new(creature_sheet).npc_action_prompt
    end
  end
end
