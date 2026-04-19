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
        @log.log!(:info, "TimeKeeper: estimated=#{estimated[:hours].round(4)}h, source=#{estimated[:source]}")

        unless estimated[:source] == :ai
          @log.play_log!("time_keeper", "#{estimated[:hours].round(4)}h (#{estimated[:source]})",
                         parsed_response: { source: estimated[:source],
                                            hours: estimated[:hours].round(4),
                                            journey_data: estimated[:journey_data] }.compact)
        end

        time_loop_data = { "hours_elapsed" => estimated[:hours].round(4), "time_source" => estimated[:source].to_s }
        time_loop_data["journey_data"] = estimated[:journey_data] if estimated[:journey_data]
        @loop&.batch_update!(
          new_data: time_loop_data,
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

        apply_fatigue_conditions(thresholds, time_ctx)
        expire_elapsed_buffs(time_ctx)

        encounter = harbinger_result if harbinger_result[:stop_reason] == :encounter

        {
          hours_elapsed: actual_hours,
          estimated_hours: estimated[:hours],
          source: estimated[:source],
          journey: estimated[:journey_data],
          encounter: encounter,
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

        raise ArgumentError, "Character sheet or derived_stats missing for journey calculation" unless @sheet&.derived_stats
        base_speed_ft = @sheet.derived_stats["speed"] || 30
        encumbrance   = @sheet.derived_stats["encumbrance"] || "light"
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
        return nil unless effective_combat_active_for_timekeeper?

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

      # AI errors (TokenBudgetExceededError, AiError) are intentionally allowed to
      # propagate here — a wrong elapsed time silently pollutes the game clock, which
      # is harder to diagnose than a visible pipeline failure. (See 46d182f.)
      def estimate_via_ai(intent, verdict_result)
        time_ctx = @adventure.time_context || {}
        outcome  = verdict_result&.dig(:outcome) || intent[:intention]
        prompt_summary = "TimeKeeper: \"#{@log.truncate(outcome)}\""

        system_prompt = PromptRenderer.render("time_keeper",
          loop: @loop,
          outcome: outcome,
          current_hour: time_ctx["current_hour"] || 8,
          adventure_day: time_ctx["adventure_day"] || 1,
          light_conditions: time_ctx["light_conditions"] || "day",
          combat_active: effective_combat_active_for_timekeeper?,
          has_destination: intent[:destination].present?)

        request_body = { system_prompt: system_prompt, user_message: intent[:intention] }

        parsed = timed_ai_call("time_keeper", prompt_summary, request_body) do
          raw = @ai.chat(system_prompt: system_prompt, user_message: intent[:intention],
                         max_tokens: @config.token_budget_for("time_keeper"),
                         step_name: "time_keeper",
                         model: @config.model_for("time_keeper"))
          [raw, @ai.parse_json(raw)]
        end

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
      end

      # ── Fatigue condition management ─────────────────────────────

      def apply_fatigue_conditions(thresholds, time_ctx)
        return unless @sheet

        if time_ctx["rest_clears_fatigue"]
          current = Array(@sheet.conditions)
          fatigue_conds = current & %w[fatigued exhausted]
          if fatigue_conds.any?
            @sheet.update!(conditions: current - fatigue_conds)
            @sheet.recompute_derived_stats!
            @log.log!(:info, "TimeKeeper: rest cleared conditions: #{fatigue_conds.join(', ')}")
          end
          return
        end

        thresholds.each do |t|
          next unless t[:type] == :fatigue && t[:condition]
          current = Array(@sheet.conditions)
          next if current.include?(t[:condition])

          upgraded = CharacterStats::Conditions.upgrade(current, t[:condition])
          @sheet.update!(conditions: upgraded.uniq)
          @sheet.recompute_derived_stats!
          @log.log!(:info, "TimeKeeper: applied condition '#{t[:condition]}' (#{t[:hours_awake]}h awake)")
        end
      end

      # ── Buff expiry ───────────────────────────────────────────────

      # Removes active_buffs entries whose expires_at_game_hours has passed
      # after the clock advances. Deterministic — no AI involved.
      def expire_elapsed_buffs(time_ctx)
        return unless @sheet&.respond_to?(:active_buffs)

        current_hour = Utilities::GameClock.absolute_hours(time_ctx)
        current = Array(@sheet.active_buffs).map(&:deep_stringify_keys)

        expired = current.select do |b|
          b["expires_at_game_hours"] && b["expires_at_game_hours"].to_f <= current_hour
        end

        return if expired.empty?

        remaining = current - expired
        @sheet.update!(active_buffs: remaining)
        @sheet.recompute_derived_stats!
        @log.log!(:info, "TimeKeeper: expired buffs at game_hour #{current_hour.round(4)}: #{expired.map { _1['source'] }.join(', ')}")
      end

      # ── Harbinger consultation ────────────────────────────────────

      def consult_harbinger_if_needed(estimated, intent)
        no_op = { interrupted: false, stop_reason: :skipped, hours_granted: estimated[:hours],
                  distance_covered_miles: 0, encounter_entry: nil }

        return no_op if effective_combat_active_for_timekeeper?
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

      # TimeKeeper runs after canonical mutations apply but before context update
      # refreshes combat_context, so it must consult live combat truth instead of
      # the lagging combat cache when deciding elapsed time and encounters.
      def effective_combat_active_for_timekeeper?
        return @effective_combat_active_for_timekeeper if defined?(@effective_combat_active_for_timekeeper)

        @effective_combat_active_for_timekeeper = if !combat_active? || @sheet.nil?
                                                    false
                                                  else
                                                    end_info = Utilities::CombatEndResolver.check_combat_end(
                                                      adventure: @adventure,
                                                      sheet: @sheet,
                                                      instant_death: @config.instant_death?
                                                    )
                                                    end_info.dig(:combat, :combat_active) == true
                                                  end
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

    end
  end
end
