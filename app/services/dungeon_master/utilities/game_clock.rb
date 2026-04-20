# frozen_string_literal: true

module DungeonMaster
  module Utilities
    # GameClock — deterministic clock advancement utility.
    #
    # Pure code, no AI. Advances the adventure's time_context by a given
    # number of hours, derives light conditions, and checks fatigue/hunger
    # thresholds. Called by TimeKeeper.
    module GameClock
      LIGHT_CONDITIONS = {
        (5..6)   => "dawn",
        (7..17)  => "day",
        (18..19) => "dusk",
      }.freeze

      FATIGUE_THRESHOLD_HOURS  = 16
      HUNGER_THRESHOLD_HOURS   = 24
      GAME_HOUR_PRECISION      = 6

      module_function

      class TimeAdvanceContext
        attr_reader :old_context, :hours, :reset_encounter_check

        def initialize(old_context:, hours:, reset_encounter_check:)
          @old_context = old_context.deep_dup
          @hours = hours.to_f
          @reset_encounter_check = reset_encounter_check
        end

        def to_h
          old_hour = (old_context["current_hour"] || 8).to_f
          old_day = (old_context["adventure_day"] || 1).to_i
          total_hours = old_hour + hours
          new_hour = total_hours % 24
          days_advanced = (total_hours / 24).floor

          updated = old_context.deep_dup
          updated["current_hour"] = new_hour.round(GAME_HOUR_PRECISION)
          updated["adventure_day"] = old_day + days_advanced
          updated["light_conditions"] = GameClock.light_for_hour(new_hour.floor)
          updated["hours_since_last_rest"] = (updated["hours_since_last_rest"] || 0).to_f + hours
          updated["hours_since_last_encounter_check"] = if reset_encounter_check
                                                          0
                                                        else
                                                          (updated["hours_since_last_encounter_check"] || 0).to_f + hours
                                                        end
          updated
        end
      end

      def advance_clock!(adventure, hours, intent: nil, reset_encounter_check: false)
        ctx = TimeAdvanceContext.new(
          old_context: (adventure.time_context || {}),
          hours: hours,
          reset_encounter_check: reset_encounter_check
        ).to_h

        if rest_action?(intent)
          ctx["hours_since_last_rest"] = 0
          ctx["rest_clears_fatigue"] = true
        end

        adventure.update!(time_context: ctx)
        ctx
      end

      def light_for_hour(hour)
        hour_int = hour.to_i % 24
        LIGHT_CONDITIONS.each { |range, cond| return cond if range.cover?(hour_int) }
        "night"
      end

      def check_thresholds(time_context)
        alerts = []
        since_rest = (time_context["hours_since_last_rest"] || 0).to_f

        if since_rest >= FATIGUE_THRESHOLD_HOURS
          condition = since_rest >= 32 ? "exhausted" : "fatigued"
          alerts << { type: :fatigue, hours_awake: since_rest.round(1), condition: condition }
        end

        alerts
      end

      # Converts a time_context hash to an absolute monotonic game-hours value.
      # Used by ActiveBuffResolver and TimeKeeper to compare expiry thresholds.
      def absolute_hours(time_context)
        ctx = time_context || {}
        (ctx["adventure_day"].to_i - 1) * 24.0 + ctx["current_hour"].to_f
      end

      def rest_action?(intent)
        return false unless intent.is_a?(Hash)

        intention = (intent[:intention] || "").downcase
        intention.match?(/\b(rest|sleep|camp|long rest|nap)\b/)
      end
    end
  end
end
