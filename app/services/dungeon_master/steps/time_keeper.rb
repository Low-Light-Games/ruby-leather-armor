# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step: TimeKeeper
    #
    # Runs after Ruling, before output phase. The single orchestrator of
    # all time-related logic in the budget pipeline:
    #
    #   1. Estimates how much in-game time the action consumed
    #      (code-first for journeys, combat, rest, take_20; AI for freeform)
    #   2. Consults Harbinger to check for encounter interruptions
    #   3. Calls GameClock to advance the adventure's time_context
    #
    # Estimation priority:
    #   Journey (known destination) → code: distance / speed_mph
    #   Journey (freeform)          → AI
    #   Combat                      → code: 6 seconds per round
    #   Rest                        → code: 8 hours (long) / 1 hour (short)
    #   Take 20                     → code: ~40 minutes
    #   Everything else             → AI
    #
    module TimeKeeper
      SPEED_FT_TO_MPH = 30.0 / 3.0

      private

      def run_time_keeper(intent, verdict_result)
        estimated = estimate_time(intent, verdict_result)
        @log.dm_log!("TimeKeeper: estimated=#{estimated[:hours].round(4)}h, source=#{estimated[:source]}")
        @loop&.batch_update!(
          new_data: { "hours_elapsed" => estimated[:hours].round(4), "time_source" => estimated[:source].to_s },
          timeline_entry: { "step" => "time_keeper", "summary" => "#{estimated[:hours].round(4)}h (#{estimated[:source]})", "at" => Time.current.iso8601 })

        harbinger_result = consult_harbinger_if_needed(estimated, intent)

        actual_hours = if harbinger_result[:interrupted]
                         harbinger_result[:hours_granted]
                       else
                         estimated[:hours]
                       end

        harbinger_consulted = harbinger_result[:stop_reason] != :skipped
        time_ctx = Utilities::GameClock.advance_clock!(@adventure, actual_hours,
                                                       intent: intent,
                                                       reset_encounter_check: harbinger_consulted)
        thresholds = Utilities::GameClock.check_thresholds(time_ctx)

        encounter = harbinger_result if harbinger_result[:stop_reason] == :encounter

        {
          hours_elapsed: actual_hours,
          estimated_hours: estimated[:hours],
          source: estimated[:source],
          journey: estimated[:journey_data],
          encounter: encounter,
          encounter_narrative: encounter&.dig(:narrative_seed),
          time_context: time_ctx,
          thresholds: thresholds,
          harbinger_result: harbinger_result
        }
      end

      # ── Estimation ────────────────────────────────────────────────

      def estimate_time(intent, verdict_result)
        journey = try_journey_estimate(intent)
        return journey if journey

        combat = try_combat_estimate
        return combat if combat

        rest = try_rest_estimate(intent)
        return rest if rest

        take20 = try_take20_estimate(intent, verdict_result)
        return take20 if take20

        estimate_via_ai(intent, verdict_result)
      end

      def try_journey_estimate(intent)
        return nil unless intent[:destination].present?

        destination_loc = resolve_destination(intent[:destination])
        return nil unless destination_loc

        origin = @adventure.current_location
        return nil unless origin

        connection = origin.connection_to(destination_loc)
        return nil unless connection

        base_speed_ft = @sheet&.derived_stats&.dig("speed") || 30
        encumbrance   = @sheet&.derived_stats&.dig("encumbrance") || "light"
        terrain       = connection.terrain_type
        distance      = connection.distance_miles.to_f

        speed_mph = compute_journey_speed(base_speed_ft, terrain)

        return nil if speed_mph <= 0

        hours = distance / speed_mph

        {
          hours: hours,
          source: :journey_code,
          terrain: terrain,
          is_journey: true,
          speed_mph: speed_mph,
          journey_data: {
            origin: origin.name,
            destination: destination_loc.name,
            distance_miles: distance,
            terrain_type: terrain,
            speed_mph: speed_mph.round(2),
            estimated_hours: hours.round(2),
            speed_factors: {
              base_speed_ft: base_speed_ft,
              encumbrance: encumbrance,
              terrain_modifier: terrain_modifier_for(terrain)
            }
          }
        }
      end

      def try_combat_estimate
        return nil unless combat_active?

        { hours: 0.0017, source: :combat_code, terrain: nil, is_journey: false,
          speed_mph: nil, journey_data: nil }
      end

      def try_rest_estimate(intent)
        intention = (intent[:intention] || "").downcase
        return nil unless intention.match?(/\b(rest|sleep|camp|long rest|nap|short rest)\b/)

        hours = intention.match?(/\bshort rest\b/) ? 1.0 : 8.0
        { hours: hours, source: :rest_code, terrain: nil, is_journey: false,
          speed_mph: nil, journey_data: nil }
      end

      def try_take20_estimate(_intent, _verdict_result)
        return nil unless @loop&.tagged?("took_20")

        { hours: 0.67, source: :take20_code, terrain: nil, is_journey: false,
          speed_mph: nil, journey_data: nil }
      end

      def estimate_via_ai(intent, verdict_result)
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raw = nil
        time_ctx = @adventure.time_context || {}
        outcome  = verdict_result&.dig(:outcome) || intent[:intention]
        prompt_summary = "TimeKeeper: \"#{@log.truncate(outcome)}\""

        system_prompt = PromptRenderer.render("time_keeper",
          outcome: outcome,
          intention: intent[:intention],
          player_intent: intent[:intention],
          current_hour: time_ctx["current_hour"] || 8,
          adventure_day: time_ctx["adventure_day"] || 1,
          light_conditions: time_ctx["light_conditions"] || "day",
          combat_active: combat_active?,
          has_destination: intent[:destination].present?)

        request_body = { system_prompt: system_prompt, user_message: intent[:intention] }
        raw = @ai.chat(system_prompt: system_prompt, user_message: intent[:intention],
                       max_tokens: @config.token_budget_for("time_keeper"),
                       step_name: "time_keeper",
                       model: @config.model_for("time_keeper"))
        parsed = @ai.parse_json(raw)
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        @log.ai_log!("time_keeper", prompt_summary, raw, parsed,
                     parse_status: @ai.last_parse_status, request_body: request_body,
                     model_used: @ai.last_model_used, duration_ms: duration_ms,
                     usage: @ai.last_usage)

        hours = (parsed["hours_elapsed"] || 0.0017).to_f.clamp(0, 720)
        distance = parsed["distance_miles"]&.to_f
        is_journey = distance.present? && distance > 0

        {
          hours: hours,
          source: :ai,
          terrain: nil,
          is_journey: is_journey,
          speed_mph: is_journey && hours > 0 ? (distance / hours) : nil,
          journey_data: is_journey ? {
            origin: @adventure.current_location&.name,
            destination: intent[:destination] || "unknown",
            distance_miles: distance,
            terrain_type: nil,
            speed_mph: hours > 0 ? (distance / hours).round(2) : 0,
            estimated_hours: hours.round(2),
            speed_factors: { source: "ai_estimate" }
          } : nil
        }
      rescue TokenBudgetExceededError => e
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        @log.ai_log_error!("time_keeper", prompt_summary || "TimeKeeper failed", e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, status: "token_budget_exceeded",
                           model_used: @ai.last_model_used, duration_ms: duration_ms,
                           usage: @ai.last_usage)
        { hours: 0.0017, source: :ai_fallback, terrain: nil, is_journey: false,
          speed_mph: nil, journey_data: nil }
      rescue AiError => e
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        @log.ai_log_error!("time_keeper", prompt_summary || "TimeKeeper failed", e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, model_used: @ai.last_model_used,
                           duration_ms: duration_ms,
                           usage: @ai.last_usage)
        { hours: 0.0017, source: :ai_fallback, terrain: nil, is_journey: false,
          speed_mph: nil, journey_data: nil }
      end

      # ── Harbinger consultation ────────────────────────────────────

      def consult_harbinger_if_needed(estimated, intent)
        no_op = { interrupted: false, stop_reason: :skipped, hours_granted: estimated[:hours],
                  distance_covered_miles: 0, narrative_seed: nil, encounter_entry: nil }

        return no_op if combat_active?
        return no_op if estimated[:hours] < 0.01

        table = EncounterTable.table_for(@adventure.story)
        return no_op unless table

        time_ctx = @adventure.time_context || {}
        since_last = (time_ctx["hours_since_last_encounter_check"] || 0).to_f
        freq = table.check_frequency_hours.to_f

        return no_op if (since_last + estimated[:hours]) < freq

        Utilities::Harbinger.consult(
          hours_needed: estimated[:hours],
          adventure: @adventure,
          terrain: estimated[:terrain],
          party_level: @sheet&.level || 1,
          speed_mph: estimated[:speed_mph],
          is_journey: estimated[:is_journey],
          ai: @ai, config: @config, log: @log,
          loop: @loop
        )
      end

      # ── Journey helpers ───────────────────────────────────────────

      def resolve_destination(destination_name)
        return nil unless destination_name.present?

        story = @adventure.story
        story.story_locations.find_by("LOWER(name) = ?", destination_name.downcase) ||
          story.story_locations.where("LOWER(name) LIKE ?", "%#{destination_name.downcase}%").first
      end

      def compute_journey_speed(base_speed_ft, terrain)
        base_mph = base_speed_ft.to_f * SPEED_FT_TO_MPH / 30.0
        modifier = terrain_modifier_for(terrain)
        base_mph * modifier
      end

      def terrain_modifier_for(terrain)
        modifiers = @config.get("terrain_speed_modifiers") || {}
        (modifiers[terrain.to_s] || 1.0).to_f
      end

      def combat_active?
        ctx = @adventure.combat_context
        ctx.is_a?(Hash) && ctx["active"] == true &&
          Array(ctx["participants"]).any?
      end
    end
  end
end
