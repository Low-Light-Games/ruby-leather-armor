# frozen_string_literal: true

module DungeonMaster
  module PromptViews
    class TimeKeeperPromptContext
      attr_reader :loop, :outcome, :current_hour, :adventure_day, :light_conditions, :combat_active, :has_destination

      def initialize(loop:, outcome:, time_context:, combat_active:, has_destination:)
        @loop = loop
        @outcome = outcome
        @current_hour = time_context["current_hour"] || 8
        @adventure_day = time_context["adventure_day"] || 1
        @light_conditions = time_context["light_conditions"] || "day"
        @combat_active = combat_active
        @has_destination = has_destination
      end
    end
  end
end
