# frozen_string_literal: true

module DungeonMaster
  module Utilities
    # TODO: Improve readability — the "no AI except for X" caveat is the smell; split the AI-driven encounter expansion into a separate collaborator so this module is genuinely deterministic.
    module Harbinger
      JOURNEY_FATIGUE_HOURS = 8

      module_function

      # @param hours_needed [Float] how many hours the caller wants
      # @param adventure [Adventure] for encounter table + location lookup
      # @param terrain [String, nil] terrain type for encounter rolls
      # @param party_level [Integer] for encounter table filtering
      # @param speed_mph [Float, nil] journey speed; nil for non-journeys
      # @param is_journey [Boolean] whether this is travel (enables distance + fatigue)
      # @param ai [Object, nil] AI client for encounter expansion (optional)
      # @param config [DmConfig, nil] for token budgets (optional)
      # @param log [Object, nil] for logging (optional)
      def consult(hours_needed:, adventure:, terrain: nil, party_level: 1,
                  speed_mph: nil, is_journey: false, ai: nil, config: nil, log: nil, loop: nil)
        table = EncounterTable.table_for(adventure.story)

        simulate_passage(
          hours: hours_needed,
          table: table,
          terrain: terrain,
          party_level: party_level,
          is_journey: is_journey,
          speed_mph: speed_mph || 0.0,
          adventure: adventure,
          ai: ai, config: config, log: log,
          loop: loop
        )
      end

      def simulate_passage(hours:, table:, terrain:, party_level:, is_journey:,
                           speed_mph:, adventure:, ai:, config:, log:, loop: nil)
        return build_result(:completed, hours, 0) if hours <= 0

        freq = table&.check_frequency_hours&.to_f || 4.0
        elapsed   = 0.0
        distance  = 0.0

        while elapsed < hours
          segment = [freq, hours - elapsed].min
          elapsed  += segment
          distance += speed_mph * segment if is_journey

          if table
            entry = table.roll_encounter(terrain: terrain, party_level: party_level)
            if entry
              enc_hours = elapsed - (segment * rand(0.2..0.8))
              enc_distance = is_journey ? (speed_mph * enc_hours) : distance
              expand_encounter(entry, adventure: adventure, ai: ai, config: config, log: log, loop: loop)

              if loop
                loop.batch_update!(
                  new_tags: { "encounter_triggered" => true },
                  new_data: { "encounter_entry_id" => entry.id, "encounter_entry_title" => entry.title },
                  timeline_entry: { "step" => "harbinger", "summary" => "Encounter: #{entry.title}", "at" => Time.current.iso8601 })
              end

              log&.play_log!("harbinger", "Encounter: #{entry.title}",
                             parsed_response: { stop_reason: "encounter", title: entry.title,
                                                hours_elapsed: enc_hours.round(2),
                                                distance_covered_miles: enc_distance.round(2) })

              return build_result(:encounter, enc_hours, enc_distance, encounter_entry: entry)
            end
          end

          if is_journey && elapsed >= JOURNEY_FATIGUE_HOURS && hours > JOURNEY_FATIGUE_HOURS
            log&.play_log!("harbinger", "Fatigue cutoff at #{elapsed.round(1)}h",
                           parsed_response: { stop_reason: "rest_needed", hours_elapsed: elapsed.round(2),
                                              distance_covered_miles: distance.round(2) })

            return build_result(:rest_needed, elapsed, distance)
          end
        end

        stop_reason = is_journey ? :arrived : :completed
        log&.play_log!("harbinger", "Clear passage: #{elapsed.round(1)}h",
                       parsed_response: { stop_reason: stop_reason, hours_elapsed: elapsed.round(2),
                                          distance_covered_miles: distance.round(2) })

        build_result(stop_reason, elapsed, distance)
      end

      def build_result(stop_reason, hours, distance, encounter_entry: nil)
        interrupted = stop_reason == :encounter || stop_reason == :rest_needed
        {
          interrupted: interrupted,
          stop_reason: stop_reason,
          hours_granted: hours.round(2),
          distance_covered_miles: (distance || 0).round(2),
          encounter_entry: encounter_entry
        }
      end

      def expand_encounter(entry, adventure:, ai:, config:, log:, loop: nil)
        if entry.fixed? || !(ai && config && log)
          loop&.batch_update!(new_data: { "encounter_scene" => entry.description.to_s.truncate(1000) })
          return entry.description
        end

        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raw = nil
        prompt_summary = "Encounter expansion: #{entry.title}"

        system_prompt, user_msg = PromptRenderer.render_with_user_message("encounter_expansion",
          hint: entry.description,
          location: adventure.current_location&.name || "the wilderness")

        request_body = { system_prompt: system_prompt, user_message: user_msg }
        raw = ai.chat(system_prompt: system_prompt, user_message: user_msg,
                      step_name: "encounter_expand", model: config.model_for("narrate"))
        parsed = ai.parse_json(raw, fallback_as: :dm_response)
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        log.ai_log!("encounter_expand", prompt_summary, raw, parsed,
                    parse_status: ai.last_parse_status, request_body: request_body,
                    model_used: ai.last_model_used, duration_ms: duration_ms,
                    usage: ai.last_usage)

        scene = parsed["scene"] || parsed["narrative"] || parsed["description"] || entry.description
        creatures = Array(parsed["creatures"]).select { |c| c.is_a?(Hash) && c["name"].present? }
        new_elements = Array(parsed["new_elements"]).select(&:present?)

        if loop
          loop_data = { "encounter_scene" => scene.to_s.truncate(1000) }
          loop_data["encounter_creatures"] = creatures if creatures.any?
          loop_data["encounter_new_elements"] = new_elements if new_elements.any?
          creature_summary = creatures.map { |c| "#{c['count'] || 1}x #{c['name']}" }.join(", ")
          summary = creatures.any? ? "Scene + #{creature_summary}" : "Scene (no creatures)"
          loop.batch_update!(
            new_data: loop_data,
            timeline_entry: { "step" => "encounter_expand", "summary" => summary, "at" => Time.current.iso8601 })
        end

        scene
      rescue => e
        log&.log!(:error, "[harbinger_expand] #{e.class}: #{e.message}")
        ApplicationErrorReporter.notify(e, context: {
          source: "harbinger_expand",
          encounter_entry_id: entry&.id,
          adventure_id: adventure&.id
        })
        entry.description
      end

      private_class_method :simulate_passage, :build_result, :expand_encounter
    end
  end
end
