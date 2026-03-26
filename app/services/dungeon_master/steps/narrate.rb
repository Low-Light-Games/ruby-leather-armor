# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step 5: Narrate.
    # Produces player-facing narrative prose from the mechanical outcome.
    module Narrate
      private

      def run_narrate(outcome, intent: nil, dm_brief: nil, encounter_triggered: false)
        broadcast_progress("Writing the story...")
        prompt_summary = "Narrate"

        time_ctx = @adventure.time_context || {}

        what_happened = @loop&.get("verdict_outcome")
        journey_data = @loop&.get("journey_data")
        encounter_scene = @loop&.get("encounter_scene")
        encounter_new_elements = @loop&.get("encounter_new_elements")

        system_prompt = PromptRenderer.render("narrate",
          dm_brief: dm_brief,
          time_context: time_ctx,
          what_happened: what_happened,
          outcome: outcome,
          pacing_text: PromptHelpers.pacing_instructions(@config),
          directed_play_text: PromptHelpers.directed_play_instructions(@adventure),
          encounter_triggered: encounter_triggered,
          journey_data: journey_data,
          encounter_scene: encounter_scene,
          encounter_new_elements: encounter_new_elements)

        unless outcome
          @log&.play_log!("pipeline_error", "Narrate step reached without an outcome — nothing to narrate",
                          parsed_response: { pipeline_outcome: outcome, encounter_scene: encounter_scene,
                                             verdict_outcome: what_happened }.compact)
          raise AiError, "Narrate step reached without an outcome — nothing to narrate"
        end
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
    end
  end
end
