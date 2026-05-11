# frozen_string_literal: true

module Encounters
  class WarmasterBridge
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
        warmaster_result = Encounters::Warmaster.initialize_from_encounter!(
          encounter_initialization_request: Encounters::Warmaster::EncounterInitializationRequest.new(
            adventure: adventure,
            encounter_entry: encounter_entry,
            creatures_data: creatures_data,
            scene_enemy_names: nil,
            sheet: sheet,
            log: log,
            config: config,
            ai: ai
          )
        )

        if warmaster_result[:status] == :awaiting_initiative
          Encounters::Warmaster.persist_pending_combat!(
            adventure: adventure,
            creature_data: warmaster_result[:creature_data]
          )

          register_spawned_creatures_as_adventure_npcs(
            adventure: adventure,
            creature_data: warmaster_result[:creature_data],
            log: log, ai: ai,
          )

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

    def self.reconcile_encounter(loop:, adventure:, intent:, log:, config:, ai:)
      encounter_scene = loop&.get("encounter_scene").to_s.presence
      verdict_outcome = loop&.get("verdict_outcome").to_s.presence

      return encounter_scene || verdict_outcome if encounter_scene.nil? || verdict_outcome.nil?

      return "#{encounter_scene}\n\n#{verdict_outcome}" unless ai && config && log

      player_action = intent[:intention].to_s
      scene_facts = SceneFacts::ForResolution.call(
        adventure:   adventure,
        intent_text: player_action,
        ai:          ai,
        log:         log,
      )

      system_prompt = Ai::PromptRenderer.render("encounter_reconciliation",
        player_action: player_action,
        player_verdict: verdict_outcome,
        encounter_scene: encounter_scene,
        scene_facts: scene_facts)

      prompt_summary = "Encounter reconciliation: \"#{player_action.truncate(80)}\""
      request_body = { system_prompt: system_prompt, user_message: "Reconcile the encounter." }

      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      ai_raw_response_text = ai.chat(system_prompt: system_prompt, user_message: "Reconcile the encounter.",
                                     step_name: "encounter_reconciliation",
                                     model: config.model_for("narrate"))
      parsed = ai.parse_json(ai_raw_response_text)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round

      log.ai_log!("encounter_reconciliation", prompt_summary, ai_raw_response_text, parsed,
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

    # Mirror Harbinger-spawned creatures into adventure_npcs so the
    # cast roster on the next player turn finds them via the existing
    # AdventureNpc tier of the deterministic lookup. Without this the
    # next CastResolver call would fall through to the bestiary tiers
    # and create a duplicate sheet for the same enemy.
    def self.register_spawned_creatures_as_adventure_npcs(adventure:, creature_data:, log:, ai:)
      records = Array(creature_data).filter_map do |row|
        next unless row.is_a?(Hash)

        c = row.deep_symbolize_keys
        next unless c[:creature_sheet_id]

        next if AdventureNpc.where(adventure_id: adventure.id, creature_sheet_id: c[:creature_sheet_id]).exists?

        Lore::NpcRecord.new(
          name:              c[:name].to_s.presence || "Creature",
          attitude:          "unfriendly",
          creature_sheet_id: c[:creature_sheet_id],
        )
      end
      return if records.empty?

      Lore::ApplyNpcs.call(
        adventure:   adventure,
        log:         log,
        ai:          ai,
        npc_records: records,
        source:      "runtime",
      )
    end

    private_class_method :reconcile_encounter, :register_spawned_creatures_as_adventure_npcs
  end
end
