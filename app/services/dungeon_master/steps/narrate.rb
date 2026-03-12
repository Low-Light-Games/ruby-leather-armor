# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step 5: Narrate.
    # Produces player-facing narrative prose from the mechanical outcome.
    module Narrate
      private

      def run_narrate(outcome, intent: nil, dm_brief: nil, encounter_triggered: false)
        prompt_summary = "Narrate"

        micro_contexts = PromptHelpers.all_micro_contexts(@adventure)
        story_context = narrate_story_context(dm_brief)
        time_ctx = @adventure.time_context || {}

        what_happened = @loop&.get("verdict_outcome")
        journey_data = @loop&.get("journey_data")
        encounter_scene = @loop&.get("encounter_scene")
        encounter_new_elements = @loop&.get("encounter_new_elements")
        encounter_creatures = @loop&.get("encounter_creatures")

        system_prompt = PromptRenderer.render("narrate",
          story_title: @adventure.story.title,
          story_context: story_context,
          story_summary: @adventure.story_summary,
          contexts_text: PromptHelpers.format_contexts(micro_contexts),
          time_context: time_ctx,
          what_happened: what_happened,
          outcome: outcome,
          pacing_text: PromptHelpers.pacing_instructions(@config),
          directed_play_text: PromptHelpers.directed_play_instructions(@adventure),
          encounter_triggered: encounter_triggered,
          journey_data: journey_data,
          encounter_scene: encounter_scene,
          encounter_new_elements: encounter_new_elements,
          encounter_has_creatures: Array(encounter_creatures).any?)

        raise AiError, "Narrate step reached without an outcome — nothing to narrate" unless outcome
        request_body = { system_prompt: system_prompt, user_message: outcome }

        parsed = timed_ai_call("narrate", prompt_summary, request_body) do
          raw = @ai.chat(system_prompt: system_prompt, user_message: outcome,
                          max_tokens: @config.token_budget_for("narrate"), step_name: "narrate",
                          model: @config.model_for("narrate"))
          # fallback_as: :dm_response is the only surviving parse fallback.
          # Unlike other steps, Narrate's output IS prose — if the model
          # returns raw text instead of JSON, the text itself is the narrative.
          [raw, @ai.parse_json(raw, fallback_as: :dm_response)]
        end

        raise AiError, "Narrate step returned no narrative — model produced: #{parsed.inspect.truncate(200)}" unless parsed["narrative"].present?

        { narrative: parsed["narrative"] }
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
