# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Fast-path step for DM queries.
    # Answers the player's question using current game state and rules
    # without advancing the scene or triggering mechanics.
    module DmQuery
      private

      def run_dm_query(sanitized_input, dm_brief: nil)
        prompt_summary = "DM Query: \"#{@log.truncate(sanitized_input)}\""

        micro_contexts = PromptHelpers.all_micro_contexts(@adventure)
        spoiler_guidance = dm_brief.present? ? "DM Brief: #{dm_brief}" : "Do NOT reveal hidden information the player's character has not yet discovered."

        system_prompt = PromptRenderer.render("dm_query",
          story_title: @adventure.story.title,
          story_summary: @adventure.story_summary,
          contexts_text: PromptHelpers.format_contexts(micro_contexts),
          guidance: Rules.guidance_for("dm_query"),
          spoiler_guidance: spoiler_guidance)

        request_body = { system_prompt: system_prompt, user_message: sanitized_input }

        parsed = timed_ai_call("dm_query", prompt_summary, request_body) do
          raw = @ai.chat(system_prompt: system_prompt, user_message: sanitized_input,
                          max_tokens: @config.token_budget_for("dm_query"), step_name: "dm_query",
                          model: @config.model_for("dm_query"))
          [raw, @ai.parse_json(raw)]
        end

        raise AiError, "DM Query step returned no answer — model produced: #{parsed.inspect.truncate(200)}" unless parsed["answer"].present?

        { answer: parsed["answer"] }
      end
    end
  end
end
