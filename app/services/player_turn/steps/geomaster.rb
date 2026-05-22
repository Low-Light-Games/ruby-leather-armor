# frozen_string_literal: true

module PlayerTurn
  module Steps
    module Geomaster
      module_function

      def turn_evaluator_prompt(inputs:, config:)
        {
          system_prompt:    render_prompt(inputs: inputs),
          user_message:     inputs.narrative.to_s,
          model:            config.model_for("geomaster"),
          reasoning_effort: config.reasoning_effort_for("geomaster"),
          meta:             { step: "geomaster" },
        }
      end

      def render_prompt(inputs:)
        Ai::PromptRenderer.render(
          "geomaster",
          known_location_names: inputs.known_location_names,
          schema_json:          Ai::PromptRenderer.load_schema("geomaster"),
        )
      end

      def parse_output(parsed)
        return Result.empty unless parsed.is_a?(Hash)

        Result.new(
          locations: Array(parsed["locations"]).select { |l| l.is_a?(Hash) && l["name"].to_s.strip.present? },
          reasoning: parsed["reasoning"].is_a?(String) ? parsed["reasoning"] : nil,
        )
      end
    end
  end
end
