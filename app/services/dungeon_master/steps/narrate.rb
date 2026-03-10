# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step 5: Narrate.
    # Produces player-facing narrative prose from the mechanical outcome.
    module Narrate
      private

      def run_narrate(outcome, player_action: nil, intent: nil, dm_brief: nil, encounter_triggered: false)
        prompt_summary = "Narrate"

        micro_contexts = PromptHelpers.all_micro_contexts(@adventure)
        story_context = narrate_story_context(dm_brief)
        time_ctx = @adventure.time_context || {}

        system_prompt = PromptRenderer.render("narrate",
          story_title: @adventure.story.title,
          story_context: story_context,
          story_summary: @adventure.story_summary,
          contexts_text: PromptHelpers.format_contexts(micro_contexts),
          time_context: time_ctx,
          outcome: outcome,
          player_action: player_action,
          player_intent: intent&.dig(:intention),
          pacing_text: PromptHelpers.pacing_instructions(@config),
          directed_play_text: PromptHelpers.directed_play_instructions(@adventure),
          encounter_triggered: encounter_triggered)

        user_msg = outcome || player_action
        raise AiError, "Narrate step reached without an outcome or player action — nothing to narrate" unless user_msg
        request_body = { system_prompt: system_prompt, user_message: user_msg }

        parsed = timed_ai_call("narrate", prompt_summary, request_body) do
          raw = @ai.chat(system_prompt: system_prompt, user_message: user_msg,
                          max_tokens: @config.token_budget_for("narrate"), step_name: "narrate",
                          model: @config.model_for("narrate"))
          [raw, @ai.parse_json(raw, fallback_as: :dm_response)]
        end

        raise AiError, "Narrate step returned no narrative — model produced: #{parsed.inspect.truncate(200)}" unless parsed["narrative"].present?

        {
          narrative: parsed["narrative"],
          adventure_complete: parsed["adventure_complete"] == true
        }
      end

      def narrate_story_context(dm_brief)
        hook = @adventure.story.hook.presence || @adventure.story.preview
        enriched_world = @adventure.enriched_world || {}
        atmosphere = enriched_world["atmosphere"]

        parts = []
        parts << "Hook: #{hook}"
        parts << "Atmosphere: #{atmosphere}" if atmosphere.present?
        parts << "DM Brief (follow these instructions carefully): #{dm_brief}" if dm_brief.present?

        parts.join("\n")
      end
    end
  end
end
