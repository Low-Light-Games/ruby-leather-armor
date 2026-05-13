# frozen_string_literal: true

module PlayerTurn
  module Steps
    module GameMaster
      RECENT_MESSAGE_LIMIT = 5
      FACT_LOOKUP_LIMIT = 8
      NPC_LOOKUP_LIMIT = 8
      LOCATION_LOOKUP_LIMIT = 6
      WEIGHTED_LOCATION_REPEATS = 3

      private

      def run_game_master(intent_text)
        broadcast_progress("Reading the situation...")

        ctx = build_game_master_context(intent_text)
        prompt_summary = "GameMaster: \"#{@log.truncate(intent_text)}\""
        system_prompt = Ai::PromptRenderer.render("game_master", ctx: ctx)
        request_body = { system_prompt: system_prompt, user_message: intent_text }

        parsed = timed_ai_call("game_master", prompt_summary, request_body) do
          raw = @ai.chat(
            system_prompt: system_prompt,
            user_message: intent_text,
            step_name: "game_master",
            model: @config.model_for("game_master"),
            reasoning_effort: @config.reasoning_effort_for("game_master")
          )
          [raw, @ai.parse_json(raw)]
        end

        narrative = parsed["narrative"].to_s.strip
        raise Ai::Error, "GameMaster returned no narrative" if narrative.empty?

        adventure_ended = parsed["adventure_ended"] == true
        player_dead = parsed["player_dead"] == true
        tool_calls = Array(parsed["tool_calls"])

        reasoning = GameMaster::Reasoning.from_parsed(parsed["reasoning"])

        @log.play_log!(
          "game_master_plan",
          "GameMaster plan: #{reasoning.display_summary.truncate(160)}",
          parsed_response: GameMaster::PlanLogPayload.new(
            reasoning: reasoning,
            narrative_chars: narrative.length,
            adventure_ended: adventure_ended,
            player_dead: player_dead,
            tool_calls: tool_calls
          ).to_h
        )

        if tool_calls.any?
          GameMaster::PendingToolsResult.new(
            lead_narrative: narrative,
            tool_calls: tool_calls,
            intent_text: intent_text
          ).to_h
        else
          GameMaster::NarratedResult.new(
            narrative: narrative,
            adventure_complete: adventure_ended,
            player_death: player_dead
          ).to_h
        end
      end

      def dispatch_game_master_tools(pending_result)
        intent_text = pending_result[:intent_text]
        tool_calls = pending_result[:tool_calls]
        lead_narrative = pending_result[:lead_narrative]

        begin
          Tools::Registry.validate_calls!(tool_calls)
        rescue Tools::Registry::ToolError => e
          @log.game_master_tool_error!(tool_calls, e, reraise_as: Ai::Error)
        end

        bind_game_master_run_to_adventure_loop(intent_text, lead_narrative)

        request_roll_result = Tools::Registry.dispatch(tool_calls, pipeline_engine: self).request_roll_result
        raise Ai::Error, "GameMaster dispatch produced no roll request" unless request_roll_result

        evaluation = EvaluationResult.new(
          intention: intent_text,
          player_rolls: [request_roll_result.to_h],
          mechanical_summary: request_roll_result.mechanical_summary,
          target_actor_sheet_id: request_roll_result.target_actor_sheet_id
        )

        @loop&.batch_update!(
          new_status: "paused",
          new_data: { "lead_narrative" => lead_narrative },
          timeline_entry: tl("awaiting_rolls", "Paused for player rolls (GM)")
        )

        GameMaster::AwaitingRollsResult.new(
          intent: evaluation.to_intent_hash,
          merged_pause_state: GameMaster::MergedPauseState.new(request_roll_result: request_roll_result),
          lead_narrative: lead_narrative
        ).to_h
      end

      def bind_game_master_run_to_adventure_loop(intent_text, lead_narrative)
        existing_adventure_loop = AdventureLoop.last_for_registry_entry(@log.registry_entry_uuid)
        loop_row = existing_adventure_loop || create_adventure_loop(intent_text, 0)
        bind_current_loop!(loop_row)
        @loop.batch_update!(
          new_status: "resolving",
          new_data: { "game_master_lead" => true, "lead_narrative_chars" => lead_narrative.length },
          timeline_entry: tl("game_master_lead", "GM emitted lead narrative + tool calls")
        )
      end

      def build_game_master_context(intent_text)
        time_ctx = @adventure.time_context.to_h.with_indifferent_access
        retrieval = retrieve_scene_for_game_master(intent_text)

        Steps::GameMaster::Context.new(
          intent_text: intent_text,
          current_location_name: @adventure.current_location&.name.presence || "(unknown)",
          current_hour: time_ctx["current_hour"] || 8,
          adventure_day: time_ctx["adventure_day"] || 1,
          light_conditions: time_ctx["light_conditions"] || "day",
          scene_facts_summary: render_scene_facts_summary(retrieval.facts),
          npcs_at_location_summary: render_nearby_npcs_summary(retrieval.npcs),
          nearby_locations_summary: render_nearby_locations_summary(retrieval.locations),
          recent_dm_messages_slice: render_recent_dm_messages,
          story_premise: @adventure.story&.premise.to_s.presence || "(no premise on file)"
        )
      end

      def retrieve_scene_for_game_master(intent_text)
        locations = retrieve_locations_for_game_master(intent_text)
        npcs = retrieve_npcs_for_game_master(intent_text, locations)
        facts = retrieve_facts_for_game_master(intent_text, locations, npcs)

        SceneRetrieval::Retrieval.new(
          facts: facts,
          locations: locations,
          npcs: npcs
        )
      end

      def retrieve_locations_for_game_master(intent_text)
        Lore::LocationsLookup.call(
          adventure: @adventure,
          ai: @ai,
          log: @log,
          query_text: game_master_locations_query(intent_text),
          limit: LOCATION_LOOKUP_LIMIT,
        )
      end

      def retrieve_npcs_for_game_master(intent_text, locations)
        Lore::NpcsLookup.call(
          adventure: @adventure,
          ai: @ai,
          log: @log,
          query_text: game_master_npcs_query(intent_text, locations),
          limit: NPC_LOOKUP_LIMIT
        )
      end

      def retrieve_facts_for_game_master(intent_text, locations, npcs)
        Lore::FactsLookup.call(
          adventure: @adventure,
          ai: @ai,
          log: @log,
          query_text: game_master_facts_query(intent_text, locations, npcs),
          limit: FACT_LOOKUP_LIMIT
        )
      end

      def game_master_locations_query(intent_text)
        location = weighted_current_location
        [intent_text, location].compact.join(" ")
      end

      def game_master_npcs_query(intent_text, locations)
        location_names = locations.first(3).map { |loc| loc[:name] }.compact
        [intent_text, weighted_current_location, location_names.join(" ")].reject(&:blank?).join(" ")
      end

      def game_master_facts_query(intent_text, locations, npcs)
        location_names = locations.first(3).map { |loc| loc[:name] }.compact
        npc_names = npcs.first(4).map { |npc| npc[:name] }.compact

        [
          intent_text,
          weighted_current_location,
          location_names.join(" "),
          npc_names.join(" ")
        ].reject(&:blank?).join(" ")
      end

      def weighted_current_location
        name = @adventure.current_location&.name.to_s.strip
        return nil if name.blank?

        ([name] * WEIGHTED_LOCATION_REPEATS).join(" ")
      end

      def render_scene_facts_summary(facts)
        return "(none retrieved)" if facts.empty?

        facts.map { |fact| "  - #{fact[:text]}" }.join("\n")
      end

      def render_nearby_npcs_summary(hits)
        return "(none retrieved)" if hits.empty?

        hits.map do |hit|
          location = hit[:location_name].presence || "unknown location"
          "  - #{hit[:name]} (#{hit[:attitude] || 'unknown attitude'}, at #{location})"
        end.join("\n")
      end

      def render_nearby_locations_summary(locations)
        return "(none retrieved)" if locations.empty?

        locations.map do |loc|
          distance = loc[:distance_miles].present? ? "#{loc[:distance_miles]}mi" : "unknown distance"
          bearing = loc[:bearing].presence || "unknown bearing"
          "  - #{loc[:name]} (#{distance}, #{bearing})"
        end.join("\n")
      end

      def render_recent_dm_messages
        rows = @adventure.adventure_messages
                         .where(role: "dm", message_type: %w[narrative action_result])
                         .order(created_at: :desc)
                         .limit(RECENT_MESSAGE_LIMIT)
                         .pluck(:content)
                         .reverse

        return "(no prior DM messages)" if rows.empty?

        rows.map.with_index(1) { |c, i| "#{i}. #{c.to_s.truncate(280)}" }.join("\n\n")
      end
    end
  end
end
