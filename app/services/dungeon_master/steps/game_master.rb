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

        @log.play_log!(
          "game_master_plan",
          "GameMaster plan: #{parsed['reasoning'].to_s.truncate(160)}",
          parsed_response: {
            reasoning: parsed["reasoning"],
            narrative_chars: narrative.length,
            adventure_ended: adventure_ended,
            player_dead: player_dead
          }
        )

        {
          action: :narrated,
          narrative: narrative,
          adventure_complete: adventure_ended,
          player_death: player_dead,
          action_outcomes: [],
          world_turn_lines: []
        }
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
