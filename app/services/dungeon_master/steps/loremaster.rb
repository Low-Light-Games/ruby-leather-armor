# frozen_string_literal: true

module DungeonMaster
  module Steps
    module Loremaster
      module_function

      def turn_evaluator_prompt(inputs:, config:)
        {
          system_prompt: render_turn_prompt(inputs: inputs),
          user_message:  inputs.what_happened.to_s,
          model:         config.model_for("loremaster"),
          meta:          { step: "loremaster" },
        }
      end

      def render_turn_prompt(inputs:)
        Ai::PromptRenderer.render(
          "loremaster",
          what_happened:  inputs.what_happened,
          mutations_json: inputs.mutations.present? ? inputs.mutations.to_json : "(no mutations)",
          active_facts:   inputs.active_facts,
          schema_json:    Ai::PromptRenderer.load_schema("loremaster"),
        )
      end

      def parse_output(parsed)
        return [[], [], nil] unless parsed.is_a?(Hash)

        facts       = Array(parsed["facts"]).select { |f| f.is_a?(Hash) }
        invalidates = Array(parsed["invalidates"]).select { |i| i.is_a?(Hash) }
        reasoning   = parsed["reasoning"].is_a?(String) ? parsed["reasoning"] : nil

        [facts, invalidates, reasoning]
      end
    end
  end
end
