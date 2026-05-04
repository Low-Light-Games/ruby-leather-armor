# frozen_string_literal: true

module DungeonMaster
  module Presenters
    # Prompt-safe text for {CreatureSheet} records (bestiary rows in combat / mech_eval).
    class CreatureSheetPromptPresenter
      def initialize(creature_sheet)
        @creature = creature_sheet
      end

      # One-line summary for mech_eval / beacon context lists.
      def stats_line
        ds = @creature.derived_stats || {}
        "#{@creature.name} (#{@creature.creature_type}): HP #{@creature.hp}/#{@creature.max_hp}, AC #{ds['ac']}, " \
          "BAB +#{ds['bab']}, Attitude: #{@creature.attitude || 'hostile'}"
      end

      def self.stats_lines_for_adventure(adventure)
        creatures = adventure.creature_sheets.to_a
        return nil if creatures.empty?

        creatures.map { |c| new(c).stats_line }.join("\n")
      end
    end
  end
end
