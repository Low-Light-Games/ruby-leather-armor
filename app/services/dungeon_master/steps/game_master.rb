# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step: GameMaster.
    #
    # Reasoning-model orchestrator that owns out-of-combat turns when the
    # `gamemaster_orchestrator` feature flag is enabled for the user.
    # First iteration is intentionally narrow: read intent + world envelope
    # + story premise, produce the player-facing prose directly. No tool
    # calls yet — that lands in the next iteration.
    module GameMaster
      RECENT_MESSAGE_LIMIT = 5
      NPC_LOOKUP_LIMIT = 8

      private

      def run_game_master(intent_text)
        broadcast_progress("Reading the situation...")

        ctx = build_game_master_context(intent_text)
        prompt_summary = "GameMaster: \"#{@log.truncate(intent_text)}\""
        system_prompt = PromptRenderer.render("game_master", ctx: ctx)
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
        raise AiError, "GameMaster returned no narrative" if narrative.empty?

        adventure_ended = parsed["adventure_ended"] == true
        player_dead = parsed["player_dead"] == true
        tool_calls = Array(parsed["tool_calls"])

        @log.play_log!(
          "game_master_plan",
          "GameMaster plan: #{parsed['reasoning'].to_s.truncate(160)}",
          parsed_response: {
            reasoning: parsed["reasoning"],
            narrative_chars: narrative.length,
            adventure_ended: adventure_ended,
            player_dead: player_dead,
            tool_calls: tool_calls
          }
        )

        if tool_calls.any?
          # The phase dispatches the tools, synthesizes the awaiting_rolls
          # result, and creates/binds the AdventureLoop. The step's job
          # ends here — return the lead narrative + parsed tool_calls.
          {
            action: :game_master_pending_tools,
            lead_narrative: narrative,
            tool_calls: tool_calls,
            intent_text: intent_text
          }
        else
          {
            action: :narrated,
            narrative: narrative,
            adventure_complete: adventure_ended,
            player_death: player_dead,
            action_outcomes: [],
            world_turn_lines: []
          }
        end
      end

      # Called by Phases::GameMaster when run_game_master returns
      # :game_master_pending_tools. Validates the tool calls, creates +
      # binds an AdventureLoop for resume linkage, dispatches the tools,
      # and synthesizes an :awaiting_rolls result with intent + merged
      # shapes compatible with RollRequestMetadata + finish_resolution.
      #
      # Errors from Tools::Registry surface as AiError so the standard
      # "DM distracted" path applies + Sentry captures the bad call.
      def dispatch_game_master_tools(pending_result)
        intent_text = pending_result[:intent_text]
        tool_calls  = pending_result[:tool_calls]
        lead_narrative = pending_result[:lead_narrative]

        begin
          Tools::Registry.validate_calls!(tool_calls)
        rescue Tools::Registry::ToolError => e
          @log.play_log!(
            "game_master_tool_error",
            "GameMaster tool validation failed: #{e.message}",
            parsed_response: { tool_calls: tool_calls, error: e.message }
          )
          raise AiError, "GameMaster emitted invalid tool call: #{e.message}"
        end

        bind_game_master_loop!(intent_text, lead_narrative)

        dispatched = Tools::Registry.dispatch(tool_calls, pipeline_engine: self)
        request_roll_result = dispatched.find { |c| c["name"] == "request_roll" }
        raise AiError, "GameMaster dispatch produced no roll spec" unless request_roll_result

        roll_spec = request_roll_result["result"]
        Rolls::PlayerRolls.assign_request_ids!([roll_spec])

        intent = {
          intention: intent_text,
          destination: nil,
          combat_transition: nil,
          combat_combatants: [],
          consequences: [],
          mechanical_summary: roll_spec[:mechanical_summary]
        }

        merged = {
          player_rolls: [roll_spec],
          npc_actions: [],
          consequences: [],
          mechanical_summaries: [roll_spec[:mechanical_summary]],
          roll_chain: nil
        }

        @loop&.batch_update!(
          new_status: "paused",
          new_data: { "lead_narrative" => lead_narrative },
          timeline_entry: tl("awaiting_rolls", "Paused for player rolls (GM)")
        )

        {
          action: :awaiting_rolls,
          intent: intent,
          merged: merged,
          remaining_actions: [],
          game_master_narrative: lead_narrative
        }
      end

      def bind_game_master_loop!(intent_text, lead_narrative)
        existing = AdventureLoop.for_registry_entry(@log.registry_entry_uuid).order(:created_at).last
        loop_row = existing || create_adventure_loop(intent_text, 0)
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
