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

      module_function

      def advance_clock!(adventure, hours, intent: nil, reset_encounter_check: false)
        ctx = (adventure.time_context || {}).deep_dup
        old_hour = (ctx["current_hour"] || 8).to_f
        old_day  = (ctx["adventure_day"] || 1).to_i

        total_hours   = old_hour + hours
        new_hour      = total_hours % 24
        days_advanced = (total_hours / 24).floor

        ctx["current_hour"]    = new_hour.round(2)
        ctx["adventure_day"]   = old_day + days_advanced
        ctx["light_conditions"] = light_for_hour(new_hour.floor)

        ctx["hours_since_last_rest"] = (ctx["hours_since_last_rest"] || 0).to_f + hours

        if reset_encounter_check
          ctx["hours_since_last_encounter_check"] = 0
        else
          ctx["hours_since_last_encounter_check"] = (ctx["hours_since_last_encounter_check"] || 0).to_f + hours
        end

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

      def rest_action?(intent)
        return false unless intent.is_a?(Hash)

        intention = (intent[:intention] || "").downcase
        intention.match?(/\b(rest|sleep|camp|long rest|nap)\b/)
      end
    end
  end
end
