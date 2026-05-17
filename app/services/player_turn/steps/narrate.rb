# frozen_string_literal: true

module PlayerTurn
  module Steps
    module Narrate
      private

      def narrate_evaluator_prompt(pipeline_context, scene_facts:, outcome_facts:)
        prompt_payload = build_narrate_prompt_payload(
          pipeline_context, scene_facts: scene_facts, outcome_facts: outcome_facts,
        )

        {
          system_prompt:    prompt_payload[:system_prompt],
          user_message:     prompt_payload[:user_message],
          model:            @config.model_for("narrate"),
          reasoning_effort: @config.reasoning_effort_for("narrate"),
          meta:             { step: "narrate", parse_fallback: "dm_response" }
        }
      end

      def narrative_from_evaluator_result(result)
        parsed = result["parsed_response"] || {}
        raise Ai::Error, "Narrate step returned no narrative — model produced: #{parsed.inspect.truncate(200)}" unless parsed["narrative"].present?

        { narrative: parsed["narrative"] }
      end

      def assert_narration_combined_seed!(pipeline_context)
        return if pipeline_context.combined_seed

        @log&.play_log!("pipeline_error", "Narrate step reached without an outcome — nothing to narrate",
                        parsed_response: { encounter_scene: @loop&.get("encounter_scene"),
                                           verdict_outcome: @loop&.get("verdict_outcome") }.compact)
        raise Ai::Error, "Narrate step reached without an outcome — nothing to narrate"
      end

      def build_narrate_prompt_payload(pipeline_context, scene_facts:, outcome_facts:)
        narrate_view = Narration::NarratePromptView.for_narrate(
          self, pipeline_context, scene_facts: scene_facts, outcome_facts: outcome_facts,
        )
        assert_narration_combined_seed!(pipeline_context)
        {
          system_prompt: Ai::PromptRenderer.render("narrate", narrate_view: narrate_view),
          user_message: pipeline_context.combined_seed
        }
      end
    end
  end
end
