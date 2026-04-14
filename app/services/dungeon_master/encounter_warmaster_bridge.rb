# frozen_string_literal: true

module DungeonMaster
  # Path A after TimeKeeper: Harbinger left encounter ids on the AdventureLoop; optionally
  # run Warmaster, update the loop, and produce the resolver return payload. Does not write
  # +pipeline_outcome+ — AdventureLoopResolution calls +store_pipeline_outcome!+ with +pipeline_outcome+.
  #
  # Scene-enemy merging: after spawning encounter-table creatures, nearby hostile NPCs
  # from traversal_context are merged in so pre-established scene enemies (e.g. goblins
  # the player was already approaching) join the combat alongside the random encounter.
  class EncounterWarmasterBridge
    # Return value from EncounterWarmasterBridge.call: resolver payload (status, intent, etc.)
    # and the string stored as the loop +pipeline_outcome+ narration seed.
    class Result
      attr_reader :payload, :pipeline_outcome

      def initialize(payload:, pipeline_outcome:)
        @payload          = payload
        @pipeline_outcome = pipeline_outcome
      end
    end

    def self.call(loop:, adventure:, sheet:, log:, config:, ai:, intent:, time_result:, mutations:)
      entry_id = loop&.get("encounter_entry_id")
      encounter_entry = EncounterTableEntry.find_by(id: entry_id) if entry_id

      if encounter_entry
        creatures_data = loop&.get("encounter_creatures")
        scene_enemy_names = extract_scene_enemy_names(adventure.traversal_context)
        warmaster_result = Utilities::Warmaster.initialize_from_encounter!(
          adventure: adventure, encounter_entry: encounter_entry,
          creatures_data: creatures_data,
          scene_enemy_names: scene_enemy_names,
          sheet: sheet, log: log, config: config, ai: ai)

        if warmaster_result[:status] == :awaiting_initiative
          loop&.batch_update!(
            new_tags: { "combat_started" => true },
            new_data: { "creature_count" => warmaster_result[:creature_data]&.size },
            timeline_entry: { "step" => "warmaster", "summary" => "Combat: #{warmaster_result[:creature_data]&.size} creature(s)", "at" => Time.current.iso8601 })

          reconciled = reconcile_encounter(loop: loop, adventure: adventure, intent: intent,
                                           log: log, config: config, ai: ai)
          return Result.new(
            payload: {
              status: :awaiting_initiative, intent: intent,
              creature_data: warmaster_result[:creature_data],
              mutations: mutations, time_result: time_result
            },
            pipeline_outcome: reconciled
          )
        end
      end

      reconciled = reconcile_encounter(loop: loop, adventure: adventure, intent: intent,
                                       log: log, config: config, ai: ai)
      Result.new(
        payload: {
          status: :encounter, intent: intent,
          mutations: mutations, time_result: time_result
        },
        pipeline_outcome: reconciled
      )
    end

    # Calls an AI step to produce a single coherent situation description from the
    # (potentially contradictory) encounter_scene and verdict_outcome. Falls back to
    # the naive join when AI is unavailable.
    def self.reconcile_encounter(loop:, adventure:, intent:, log:, config:, ai:)
      encounter_scene = loop&.get("encounter_scene").to_s.presence
      verdict_outcome = loop&.get("verdict_outcome").to_s.presence

      # If only one side exists there is nothing to reconcile.
      return encounter_scene || verdict_outcome if encounter_scene.nil? || verdict_outcome.nil?
      return "#{encounter_scene}\n\n#{verdict_outcome}" unless ai && config && log

      player_action = intent[:intention].to_s
      traversal = adventure.traversal_context || {}
      context_summary = [
        traversal["scene"].presence,
        ("Location: #{traversal['current_location']}" if traversal["current_location"].present?),
        ("Nearby: #{traversal['nearby_npcs'].join(', ')}" if traversal["nearby_npcs"].present?)
      ].compact.join("\n")

      system_prompt = PromptRenderer.render("encounter_reconciliation",
        player_action: player_action,
        player_verdict: verdict_outcome,
        encounter_scene: encounter_scene,
        context_summary: context_summary.presence || "(no traversal context)")

      prompt_summary = "Encounter reconciliation: \"#{player_action.truncate(80)}\""
      request_body = { system_prompt: system_prompt, user_message: "Reconcile the encounter." }

      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      raw = ai.chat(system_prompt: system_prompt, user_message: "Reconcile the encounter.",
                    max_tokens: config.token_budget_for("narrate"),
                    step_name: "encounter_reconciliation",
                    model: config.model_for("narrate"))
      parsed = ai.parse_json(raw)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round

      log.ai_log!("encounter_reconciliation", prompt_summary, raw, parsed,
                  parse_status: ai.last_parse_status, request_body: request_body,
                  model_used: ai.last_model_used, duration_ms: duration_ms,
                  usage: ai.last_usage)

      situation = parsed["situation"].presence
      player_spotted = parsed["player_spotted"]

      loop&.batch_update!(
        new_data: { "player_spotted_at_encounter" => player_spotted },
        timeline_entry: { "step" => "encounter_reconciliation",
                          "summary" => "Reconciled: player_spotted=#{player_spotted}",
                          "at" => Time.current.iso8601 })

      situation || "#{encounter_scene}\n\n#{verdict_outcome}"
    rescue => e
      log&.log!(:error, "[encounter_reconciliation] #{e.class}: #{e.message}")
      ApplicationErrorReporter.notify(e, context: {
        source: "encounter_reconciliation",
        adventure_id: adventure&.id
      })
      "#{encounter_scene}\n\n#{verdict_outcome}"
    end

    # Words at the start of a nearby_npcs entry that indicate the NPC is not an
    # immediate threat and should not be pulled into the encounter.
    SCENE_ENEMY_PASSIVE_MARKERS = %w[distant far fleeing fled invisible hiding escaped dead].freeze

    # Articles, determiners and number words to strip before extracting the creature name.
    SCENE_ENEMY_SKIP_LEADING = %w[a an the one two three four five six several some many
                                  group pack band patrol squad].freeze

    # Extracts hostile NPC names from traversal_context["nearby_npcs"] for merging into
    # a Harbinger-triggered combat. Filters out clearly distant or passive entries and
    # returns up to 2 meaningful words per entry (enough for fuzzy bestiary matching).
    def self.extract_scene_enemy_names(traversal_context)
      nearby = Array(traversal_context&.dig("nearby_npcs") || traversal_context&.dig(:nearby_npcs))
      nearby.filter_map do |entry|
        str = entry.to_s.strip
        lower = str.downcase
        next if SCENE_ENEMY_PASSIVE_MARKERS.any? { |w| lower.start_with?(w) }

        words = str.split.reject { |w| SCENE_ENEMY_SKIP_LEADING.include?(w.downcase) }
        name = words.take(2).join(" ").gsub(/[^a-zA-Z\s'-]/, "").strip
        name.presence
      end.uniq
    end

    private_class_method :reconcile_encounter, :extract_scene_enemy_names
  end
end
