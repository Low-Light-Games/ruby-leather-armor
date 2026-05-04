# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Fast-path step for DM queries.
    # Answers the player's question using current game state and rules
    # without advancing the scene or triggering mechanics.
    module DmQuery
      private

      def run_dm_query(sanitized_input)
        prompt_summary = "DM Query: \"#{@log.truncate(sanitized_input)}\""

        scene_retrieval = DungeonMaster::SceneRetrieval::ForResolution.call(
          adventure:   @adventure,
          intent_text: sanitized_input,
          ai:          @ai,
          log:         @log,
        )
        battlefield_slice = Battlefield::PromptSerializer.slice_for_adventure(@adventure)

        system_prompt = PromptRenderer.render("dm_query",
          story_title: @adventure.story.title,
          story_summary: @adventure.story_summary,
          scene_retrieval: scene_retrieval,
          current_location_name: @adventure.current_location&.name,
          battlefield_slice: battlefield_slice.presence || "(no tactical map loaded)",
          guidance: Rules.guidance_for("dm_query"))

        request_body = { system_prompt: system_prompt, user_message: sanitized_input }

        parsed = timed_ai_call("dm_query", prompt_summary, request_body) do
          raw = @ai.chat(system_prompt: system_prompt, user_message: sanitized_input,
                          step_name: "dm_query", model: @config.model_for("dm_query"))
          [raw, @ai.parse_json(raw)]
        end

        raise AiError, "DM Query step returned no answer — model produced: #{parsed.inspect.truncate(200)}" unless parsed["answer"].present?

        { answer: parsed["answer"] }
      end
    end
  end
end
