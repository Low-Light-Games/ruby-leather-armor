# frozen_string_literal: true

module DungeonMaster
  module Utilities
    # Harbinger — deterministic encounter-checking utility.
    #
    # Pure code (dice rolls against encounter tables), no AI except for
    # optional encounter narrative expansion. Called by TimeKeeper when
    # significant time passes. Simulates the passage in segments, rolls
    # for encounters per segment, and may grant fewer hours than requested
    # if an encounter or fatigue interrupts.
    #
    # Does NOT compute speed, distance, or destinations — those are
    # provided by the caller (TimeKeeper).
    module Harbinger
      JOURNEY_FATIGUE_HOURS = 8

      module_function

      # Main entry point. Returns a result hash.
      #
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
                  speed_mph: nil, is_journey: false, ai: nil, config: nil, log: nil)
        table = EncounterTable.table_for(adventure.story)

        simulate_passage(
          hours: hours_needed,
          table: table,
          terrain: terrain,
          party_level: party_level,
          is_journey: is_journey,
          speed_mph: speed_mph || 0.0,
          adventure: adventure,
          ai: ai, config: config, log: log
        )
      end

      def simulate_passage(hours:, table:, terrain:, party_level:, is_journey:,
                           speed_mph:, adventure:, ai:, config:, log:)
        return build_result(:completed, hours, 0, nil) if hours <= 0

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
              narrative = expand_encounter(entry, adventure: adventure, ai: ai, config: config, log: log)
              return build_result(:encounter, enc_hours, enc_distance, narrative, encounter_entry: entry)
            end
          end

          if is_journey && elapsed >= JOURNEY_FATIGUE_HOURS && hours > JOURNEY_FATIGUE_HOURS
            return build_result(
              :rest_needed, elapsed, distance,
              "After #{elapsed.round(1)} hours of travel, fatigue sets in. Time to rest."
            )
          end
        end

        build_result(is_journey ? :arrived : :completed, elapsed, distance, nil)
      end

      def build_result(stop_reason, hours, distance, narrative_seed, encounter_entry: nil)
        interrupted = stop_reason == :encounter || stop_reason == :rest_needed
        {
          interrupted: interrupted,
          stop_reason: stop_reason,
          hours_granted: hours.round(2),
          distance_covered_miles: (distance || 0).round(2),
          narrative_seed: narrative_seed,
          encounter_entry: encounter_entry
        }
      end

      def expand_encounter(entry, adventure:, ai:, config:, log:)
        return entry.description if entry.fixed?
        return entry.description unless ai && config && log

        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raw = nil
        prompt_summary = "Encounter expansion: #{entry.title}"

        system_prompt = PromptRenderer.render("encounter_expansion",
          hint: entry.description,
          location: adventure.current_location&.name || "the wilderness",
          traversal_context: adventure.traversal_context)

        request_body = { system_prompt: system_prompt, user_message: "Expand this encounter." }
        raw = ai.chat(system_prompt: system_prompt, user_message: "Expand this encounter.",
                      max_tokens: config.token_budget_for("narrate"), step_name: "encounter_expand",
                      model: config.model_for("narrate"))
        parsed = ai.parse_json(raw, fallback_as: :dm_response)
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        log.ai_log!("encounter_expand", prompt_summary, raw, parsed,
                    parse_status: ai.last_parse_status, request_body: request_body,
                    model_used: ai.last_model_used, duration_ms: duration_ms,
                    usage: ai.last_usage)

        parsed["scene"] || parsed["narrative"] || parsed["description"] || entry.description
      rescue => e
        log&.dm_log!("Encounter expansion failed: #{e.message} — using raw description")
        entry.description
      end

      private_class_method :simulate_passage, :build_result, :expand_encounter
    end
  end
end
