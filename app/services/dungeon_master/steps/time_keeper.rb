# frozen_string_literal: true

module DungeonMaster
  module Steps
    # TODO: Improve readability — name the dispatch methods after the waterfall branches so the source reads as the table rather than restating it in prose.
    module TimeKeeper
      SPEED_FT_TO_MPH = 30.0 / 3.0

      private

      def run_time_keeper(intent, verdict_result)
        estimated = estimate_time(intent, verdict_result)
        @log.log!(:info, "TimeKeeper: estimated=#{estimated[:hours].round(4)}h, source=#{estimated[:source]}")

        unless estimated[:source] == :ai
          @log.ai_log!(
            "time_keeper",
            "#{estimated[:hours].round(4)}h (#{estimated[:source]})",
            nil,
            { source: estimated[:source],
              hours: estimated[:hours].round(4),
              journey_data: estimated[:journey_data] }.compact,
            parse_status: "pipeline_event",
            request_body: deterministic_step_inputs(intent, verdict_result),
          )
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

        update_player_position!(estimated, harbinger_result, actual_hours)

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
        raw_destination = intent[:destination] || intent["destination"]
        return nil if raw_destination.blank?

        destination = resolve_destination(raw_destination)
        return nil unless destination

        origin = origin_adventure_location
        return nil unless origin

        unless @sheet&.derived_stats
          raise ArgumentError, "Character sheet or derived_stats missing for journey calculation"
        end

        base_speed_ft  = @sheet.derived_stats["speed"] || 30
        encumbrance    = @sheet.derived_stats["encumbrance"] || "light"
        terrain        = @adventure.story.world_terrain
        distance_miles = euclidean_distance_in_miles(origin, destination)

        speed_mph = compute_journey_speed(base_speed_ft, terrain)
        return nil if speed_mph <= 0

        hours = distance_miles / speed_mph

        {
          hours: hours,
          source: :journey_code,
          terrain: terrain,
          is_journey: true,
          speed_mph: speed_mph,
          journey_data: {
            origin: origin.name,
            destination: destination.name,
            distance_miles: distance_miles,
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

      def origin_adventure_location
        @adventure.current_location
      end

      def euclidean_distance_in_miles(origin, destination)
        dx = destination.x - origin.x
        dy = destination.y - origin.y
        unit_distance = Math.sqrt(dx * dx + dy * dy)
        unit_distance * @adventure.coordinate_scale.to_f
      end

      # Captured into the deterministic ai_log's request_body so admins can
      # debug branch selection / numeric inputs the same way they read AI
      # call parameters.
      def deterministic_step_inputs(intent, verdict_result)
        loc = @adventure.current_location
        {
          intent: {
            intention: intent[:intention] || intent["intention"],
            destination: intent[:destination] || intent["destination"],
            transition: intent[:transition] || intent["transition"],
            combat_combatants: intent[:combat_combatants] || intent["combat_combatants"],
          }.compact,
          verdict: verdict_result,
          sheet: @sheet ? {
            speed: @sheet.derived_stats&.dig("speed"),
            encumbrance: @sheet.derived_stats&.dig("encumbrance"),
          } : nil,
          adventure: {
            id: @adventure.id,
            current_location_id: @adventure.current_location_id,
            current_location_name: loc&.name,
            current_location_xy: loc ? [loc.x, loc.y] : nil,
            coordinate_scale: @adventure.coordinate_scale.to_f,
            world_terrain: @adventure.story&.world_terrain,
            combat_active: effective_combat_active_for_timekeeper?,
          },
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

      # AI errors (Ai::TokenBudgetExceededError, Ai::Error) are intentionally allowed to
      # propagate here — a wrong elapsed time silently pollutes the game clock, which
      # is harder to diagnose than a visible pipeline failure. (See 46d182f.)
      def estimate_via_ai(intent, verdict_result)
        time_ctx = @adventure.time_context || {}
        outcome  = verdict_result&.dig(:outcome) || intent[:intention]
        prompt_summary = "TimeKeeper: \"#{@log.truncate(outcome)}\""
        prompt_context = PromptViews::TimeKeeperPromptContext.new(
          loop: @loop,
          outcome: outcome,
          time_context: time_ctx,
          combat_active: effective_combat_active_for_timekeeper?,
          has_destination: intent[:destination].present?
        )

        system_prompt = Ai::PromptRenderer.render("time_keeper",
          time_keeper_context: prompt_context)

        request_body = { system_prompt: system_prompt, user_message: intent[:intention] }

        parsed = timed_ai_call("time_keeper", prompt_summary, request_body) do
          raw = @ai.chat(system_prompt: system_prompt, user_message: intent[:intention],
                         step_name: "time_keeper",
                         model: @config.model_for("time_keeper"))
          [raw, @ai.parse_json(raw)]
        end

        raw_hours = parsed["hours_elapsed"]
        if raw_hours.nil?
          raise Ai::Error, "TimeKeeper AI returned no hours_elapsed (parsed: #{parsed.inspect.truncate(200)})"
        end

        hours = raw_hours.to_f.clamp(0, 720)
        hours = enforce_destination_floor(hours, intent)

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

      # When a destination is named but the AI emitted a combat-grade duration,
      # the model treated "walk to X" as a Move action. Floor the elapsed time
      # so the clock and Harbinger see real travel hours; loud play_log entry
      # makes the override visible.
      DESTINATION_AI_FLOOR_HOURS = 0.25

      def enforce_destination_floor(hours, intent)
        return hours unless (intent[:destination] || intent["destination"]).present?

        return hours if hours >= DESTINATION_AI_FLOOR_HOURS

        @log&.play_log!(
          "time_keeper_ai_floor",
          "AI estimated #{hours.round(4)}h with a destination set; flooring to #{DESTINATION_AI_FLOOR_HOURS}h.",
          parsed_response: { ai_hours: hours, floor: DESTINATION_AI_FLOOR_HOURS,
                             destination: intent[:destination] || intent["destination"] },
        )
        DESTINATION_AI_FLOOR_HOURS
      end

      # ── Fatigue condition management ─────────────────────────────

      def apply_fatigue_conditions(thresholds, time_ctx)
        return unless @sheet

        if time_ctx["rest_clears_fatigue"]
          current = CharacterStats::PersistedJsonArray.list(@sheet.conditions)
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

          current = CharacterStats::PersistedJsonArray.list(@sheet.conditions)
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
        current = CharacterStats::PersistedJsonArray.list(@sheet.active_buffs).map(&:deep_stringify_keys)

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

        Encounters::Harbinger.consult(
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
                                                    end_info = Combat::EndResolver.check_combat_end(
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

        haystack = destination_name.downcase
        scope = AdventureLocation.for_adventure(@adventure)
        exact = scope.find_by("LOWER(name) = ?", haystack)
        return exact if exact

        # Prefer locations whose name appears verbatim in the
        # destination (handles polluted strings like
        # "Garrison Keep (7.07 miles southwest) or ..."). Pick the
        # longest matching name to favour "Garrison Keep" over a
        # shorter "Keep" when both fit.
        contained_in_destination = scope.where("? LIKE '%' || LOWER(name) || '%'", haystack)
                                        .max_by { |loc| loc.name.length }
        return contained_in_destination if contained_in_destination

        # Fall back to the older direction (handles shortenings:
        # "keep" → "Garrison Keep"). Pick the shortest matching name
        # to favour the most specific match.
        scope.where("LOWER(name) LIKE ?", "%#{haystack}%").min_by { |loc| loc.name.length }
      end

      def update_player_position!(estimated, harbinger_result, actual_hours)
        return unless estimated[:source] == :journey_code

        return if estimated[:hours].to_f <= 0

        from = origin_adventure_location
        to   = resolve_destination(estimated[:journey_data][:destination])
        return unless from && to

        if harbinger_result[:interrupted]
          fraction = actual_hours.to_f / estimated[:hours].to_f
          site = Adventures::EncounterSiteCreator.create!(
            adventure: @adventure, from: from, to: to,
            fraction: fraction, ai: @ai, log: @log
          )
          @adventure.update!(current_location_id: site.id) if site
        else
          @adventure.update!(current_location_id: to.id)
        end
      rescue StandardError => e
        @log.report_error(e, context: { step: "time_keeper.update_player_position",
                                        adventure_id: @adventure&.id })
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
