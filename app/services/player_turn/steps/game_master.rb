# frozen_string_literal: true

module PlayerTurn
  module Steps
    module GameMaster
      RECENT_MESSAGE_LIMIT = 5
      NPC_LOOKUP_LIMIT = 8

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

        Steps::GameMaster::Context.new(
          intent_text: intent_text,
          current_location_name: @adventure.current_location&.name.presence || "(unknown)",
          current_hour: time_ctx["current_hour"] || 8,
          adventure_day: time_ctx["adventure_day"] || 1,
          light_conditions: time_ctx["light_conditions"] || "day",
          npcs_at_location_summary: render_nearby_npcs_summary(intent_text),
          recent_dm_messages_slice: render_recent_dm_messages,
          story_premise: @adventure.story&.premise.to_s.presence || "(no premise on file)"
        )
      end

      def render_nearby_npcs_summary(intent_text)
        hits = Lore::NpcsLookup.new(
          adventure: @adventure,
          ai: @ai,
          log: @log,
          query_text: [intent_text, @adventure.current_location&.name].compact.join(" — "),
          limit: NPC_LOOKUP_LIMIT
        ).call

        return "(none known)" if hits.empty?

        hits.map { |h| "  - #{h[:name]} (#{h[:attitude] || 'unknown attitude'})" }.join("\n")
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
