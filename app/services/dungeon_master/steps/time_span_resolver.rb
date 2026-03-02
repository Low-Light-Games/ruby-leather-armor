# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Deterministic time-span resolution: runs AFTER ruling+evaluate.
    # Simulates the passage of time in segments, rolling for encounters.
    # Supports journey, rest, wait, and activity types.
    module TimeSpanResolver
      private

      SPEED_FT_TO_MPH = 30.0 / 3.0 # 30ft base = ~3 mph walking

      def run_time_span(intent, eval_result, ruling_merged)
        span_type = (intent[:time_span_type] || "journey").to_s
        time_span_params = extract_time_span_params(ruling_merged)
        eval_mutations = eval_result[:mutations] || {}
        travel_eval = (eval_mutations["time_span"] || eval_mutations[:time_span] || {}).deep_symbolize_keys

        effective_hours = compute_effective_hours(span_type, intent, time_span_params, travel_eval)
        @log.dm_log!("TimeSpan: type=#{span_type}, effective_hours=#{effective_hours}")

        table = EncounterTable.table_for(@adventure.story)
        terrain = current_terrain(intent)
        party_level = @sheet&.level || 1

        resolution = simulate_segments(
          span_type: span_type,
          effective_hours: effective_hours,
          table: table,
          terrain: terrain,
          party_level: party_level,
          time_span_params: time_span_params,
          travel_eval: travel_eval,
          intent: intent
        )

        resolution[:ruling_summary] = ruling_merged[:ruling_summaries]&.join("; ")
        resolution[:time_span_type] = span_type
        resolution
      end

      def simulate_segments(span_type:, effective_hours:, table:, terrain:, party_level:, time_span_params:, travel_eval:, intent:)
        return resolve_no_duration(span_type, intent) if effective_hours <= 0

        freq = table&.check_frequency_hours || 4
        hours_elapsed = 0.0
        distance_covered = 0.0
        speed_mph = (time_span_params[:effective_speed_mph] || default_speed_mph).to_f
        speed_factor = (travel_eval[:speed_penalty_factor] || 1.0).to_f
        effective_speed = speed_mph * speed_factor

        forced_stop_hour = travel_eval[:forced_stop_hour]&.to_f

        while hours_elapsed < effective_hours
          segment_hours = [freq.to_f, effective_hours - hours_elapsed].min

          if forced_stop_hour && (hours_elapsed + segment_hours) > forced_stop_hour
            partial = forced_stop_hour - hours_elapsed
            hours_elapsed = forced_stop_hour
            distance_covered += effective_speed * partial if span_type == "journey"
            return build_result(:exhaustion, span_type, hours_elapsed, distance_covered, intent,
                                "Character forced to stop due to #{travel_eval[:forced_stop_reason] || 'exhaustion'}")
          end

          hours_elapsed += segment_hours
          distance_covered += effective_speed * segment_hours if span_type == "journey"

          if table
            entry = table.roll_encounter(terrain: terrain, party_level: party_level)
            if entry
              encounter_hours = hours_elapsed - (segment_hours * rand(0.2..0.8))
              encounter_distance = effective_speed * encounter_hours if span_type == "journey"
              narrative = expand_encounter_entry(entry)
              return build_result(:encounter, span_type, encounter_hours, encounter_distance || distance_covered, intent, narrative, entry)
            end
          end

          if span_type == "journey" && hours_elapsed >= 8 && effective_hours > 8 && !forced_stop_hour
            total_distance = journey_distance(intent)
            if total_distance && distance_covered < total_distance
              return build_result(:rest_needed, span_type, hours_elapsed, distance_covered, intent,
                                  "After #{hours_elapsed.round(1)} hours of travel, fatigue sets in. Time to rest.")
            end
          end
        end

        stop_reason = case span_type
                      when "journey"    then :arrived
                      when "rest"       then :rest_complete
                      when "wait"       then :event_occurred
                      when "activity"   then :activity_complete
                      else :completed
                      end

        build_result(stop_reason, span_type, hours_elapsed, distance_covered, intent,
                     completion_narrative(span_type, hours_elapsed, intent))
      end

      def build_result(stop_reason, span_type, hours, distance, intent, narrative_seed, encounter_entry = nil)
        mutations = { "time_span" => { "hours_elapsed" => hours.round(2), "type" => span_type } }

        if span_type == "journey"
          total_dist = journey_distance(intent)
          arrived = stop_reason == :arrived && total_dist && distance >= total_dist
          dest_location = resolve_destination(intent)

          mutations["time_span"]["distance_covered_miles"] = distance.round(2)
          mutations["time_span"]["new_location_id"] = dest_location&.id if arrived
          mutations["time_span"]["arrived"] = arrived
        end

        {
          stop_reason: stop_reason,
          narrative_seed: narrative_seed,
          hours_elapsed: hours.round(2),
          distance_covered_miles: (distance || 0).round(2),
          encounter_entry: encounter_entry,
          mutations: mutations
        }
      end

      def compute_effective_hours(span_type, intent, time_span_params, travel_eval)
        eval_hours = travel_eval[:effective_hours]&.to_f
        return eval_hours if eval_hours && eval_hours > 0

        case span_type
        when "journey"
          time_span_params[:estimated_hours]&.to_f || compute_journey_hours(intent, time_span_params)
        when "rest"
          intent[:estimated_hours] || 8.0
        when "wait"
          intent[:estimated_hours] || time_span_params[:estimated_hours]&.to_f || 4.0
        when "activity"
          intent[:estimated_hours] || time_span_params[:estimated_hours]&.to_f || 4.0
        else
          4.0
        end
      end

      def compute_journey_hours(intent, time_span_params)
        dist = journey_distance(intent)
        return 4.0 unless dist

        speed = (time_span_params[:effective_speed_mph] || default_speed_mph).to_f
        speed = default_speed_mph if speed <= 0
        dist / speed
      end

      def journey_distance(intent)
        dest = resolve_destination(intent)
        return nil unless dest && @adventure.current_location

        @adventure.current_location.distance_to(dest)
      end

      def resolve_destination(intent)
        return nil unless intent[:destination].present?

        story = @adventure.story
        story.story_locations.find_by("LOWER(name) = ?", intent[:destination].downcase) ||
          story.story_locations.where("LOWER(name) LIKE ?", "%#{intent[:destination].downcase}%").first
      end

      def current_terrain(intent)
        return nil unless @adventure.current_location

        dest = resolve_destination(intent)
        return nil unless dest

        conn = @adventure.current_location.connection_to(dest)
        conn&.terrain_type
      end

      def default_speed_mph
        base_speed = @sheet&.derived_stats&.dig("speed") || 30
        base_speed.to_f * SPEED_FT_TO_MPH / 30.0
      end

      def expand_encounter_entry(entry)
        return entry.description if entry.fixed?

        raw = nil
        prompt_summary = "Encounter expansion: #{entry.title}"

        system_prompt = PromptRenderer.render("time_span_encounter",
          hint: entry.description,
          location: @adventure.current_location&.name || "the wilderness",
          traversal_context: @adventure.traversal_context)

        request_body = { system_prompt: system_prompt, user_message: "Expand this encounter." }
        raw = @ai.chat(system_prompt: system_prompt, user_message: "Expand this encounter.",
                        max_tokens: @config.token_budget_for("narrate"), step_name: "encounter_expand",
                        model: @config.model_for("narrate"))
        parsed = @ai.parse_json(raw, fallback_as: :dm_response)
        @log.ai_log!("encounter_expand", prompt_summary, raw, parsed,
                     parse_status: @ai.last_parse_status, request_body: request_body,
                     model_used: @ai.last_model_used)

        parsed["scene"] || parsed["narrative"] || parsed["description"] || entry.description
      rescue => e
        @log.dm_log!("Encounter expansion failed: #{e.message} — using raw description")
        entry.description
      end

      def resolve_no_duration(span_type, intent)
        build_result(:completed, span_type, 0, 0, intent, "The action completes immediately.")
      end

      def completion_narrative(span_type, hours, intent)
        case span_type
        when "journey"
          dest = intent[:destination] || "the destination"
          "After #{hours.round(1)} hours of travel, #{dest} comes into view."
        when "rest"
          "After #{hours.round(1)} hours of rest, you feel refreshed."
        when "wait"
          "After #{hours.round(1)} hours of waiting, the moment arrives."
        when "activity"
          "After #{hours.round(1)} hours of focused effort, the task is complete."
        else
          "#{hours.round(1)} hours pass."
        end
      end

      def extract_time_span_params(ruling_merged)
        first_ruling = ruling_merged.is_a?(Hash) ? ruling_merged : {}
        if ruling_merged.is_a?(Hash) && ruling_merged[:ruling_summaries]
          first_ruling = {}
        end

        # Time-span params come from the ruling's type-specific parameters hash
        # stored on the ruling by run_time_span_ruling
        params = {}
        if ruling_merged.is_a?(Array)
          ruling_merged.each do |r|
            params.merge!(r[:time_span_parameters] || {})
          end
        end
        params
      end
    end
  end
end
