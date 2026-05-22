# frozen_string_literal: true

module PlayerTurn
  module Steps
    module SocialMaster
      module_function

      def turn_evaluator_prompt(inputs:, config:)
        {
          system_prompt:    render_prompt(inputs: inputs),
          user_message:     inputs.narrative.to_s,
          model:            config.model_for("social_master"),
          reasoning_effort: config.reasoning_effort_for("social_master"),
          meta:             { step: "social_master" },
        }
      end

      def render_prompt(inputs:)
        Ai::PromptRenderer.render(
          "social_master",
          known_npc_names: inputs.known_npc_names,
          schema_json:     Ai::PromptRenderer.load_schema("social_master"),
        )
      end

      def parse_output(parsed)
        return Result.empty unless parsed.is_a?(Hash)

        Result.new(
          npcs: Array(parsed["npcs"]).select { |n| n.is_a?(Hash) && n["name"].to_s.strip.present? },
          reasoning: parsed["reasoning"].is_a?(String) ? parsed["reasoning"] : nil,
        )
      end
    end
  end
end
