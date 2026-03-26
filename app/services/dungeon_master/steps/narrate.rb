# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step 5: Narrate.
    # Produces player-facing narrative prose from the mechanical outcome.
    # Receives a PipelineContext covering the full turn (all loops), not just
    # the last action's loop.
    module Narrate
      private

      def run_narrate(pipeline)
        broadcast_progress("Writing the story...")
        prompt_summary = "Narrate"

        system_prompt = PromptRenderer.render("narrate",
          loop: @loop,
          pipeline: pipeline,
          time_context: @adventure.time_context || {},
          pacing_text: PromptHelpers.pacing_instructions(@config),
          directed_play_text: PromptHelpers.directed_play_instructions(@adventure))

        unless pipeline.combined_seed
          @log&.play_log!("pipeline_error", "Narrate step reached without an outcome — nothing to narrate",
                          parsed_response: { encounter_scene: @loop&.get("encounter_scene"),
                                             verdict_outcome: @loop&.get("verdict_outcome") }.compact)
          raise AiError, "Narrate step reached without an outcome — nothing to narrate"
        end

        request_body = { system_prompt: system_prompt, user_message: pipeline.combined_seed }

        parsed = timed_ai_call("narrate", prompt_summary, request_body) do
          raw = @ai.chat(system_prompt: system_prompt, user_message: pipeline.combined_seed,
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
