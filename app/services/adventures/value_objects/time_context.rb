# frozen_string_literal: true

module Adventures
  module ValueObjects
    class TimeContext
      attr_reader :hour, :adventure_day, :hours_since_last_rest, :hours_since_last_encounter_check

      def initialize(hour:, adventure_day: 1, hours_since_last_rest: 0, hours_since_last_encounter_check: 0)
        @hour = hour.to_i.clamp(0, 23)
        @adventure_day = adventure_day.to_i
        @hours_since_last_rest = hours_since_last_rest.to_f
        @hours_since_last_encounter_check = hours_since_last_encounter_check.to_f
      end

      def to_h
        {
          "current_hour" => hour,
          "adventure_day" => adventure_day,
          "light_conditions" => Adventures::GameClock.light_for_hour(hour),
          "hours_since_last_rest" => hours_since_last_rest,
          "hours_since_last_encounter_check" => hours_since_last_encounter_check
        }
      end
    end
  end
end
