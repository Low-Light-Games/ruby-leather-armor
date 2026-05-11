# frozen_string_literal: true

module PlayerTurn
  module Presenters
    class AdventureActorSheetPromptPresenter
      def initialize(adventure_actor_sheet)
        @creature = adventure_actor_sheet
      end

      def stats_line
        ds = @creature.derived_stats || {}
        "#{@creature.name} (#{@creature.creature_type}): HP #{@creature.hp}/#{@creature.max_hp}, AC #{ds['ac']}, " \
          "BAB +#{ds['bab']}, Attitude: #{@creature.attitude || 'hostile'}"
      end

      def self.stats_lines_for_adventure(adventure)
        creatures = adventure.adventure_actor_sheets.to_a
        return nil if creatures.empty?

        creatures.map { |c| new(c).stats_line }.join("\n")
      end
    end
  end
end
