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
          max_tokens:    config.token_budget_for("loremaster"),
          meta:          { step: "loremaster" },
        }
      end

      def render_seed_prompt(premise:, enriched_world:, opening_narrative:,
                             initial_contexts_text:, npcs_text:, clues_text:,
                             locations_text:)
        PromptRenderer.render(
          "loremaster",
          call_shape: "seed",
          premise: premise,
          enriched_world: enriched_world,
          opening_narrative: opening_narrative,
          initial_contexts_text: initial_contexts_text,
          npcs_text: npcs_text,
          clues_text: clues_text,
          locations_text: locations_text,
          schema_json: PromptRenderer.load_schema("loremaster"),
        )
      end

      def render_turn_prompt(inputs:)
        PromptRenderer.render(
          "loremaster",
          call_shape: "turn",
          what_happened: inputs.what_happened,
          mutations_json: inputs.mutations.present? ? inputs.mutations.to_json : "(no mutations)",
          contexts_text: inputs.contexts_text,
          active_facts: inputs.active_facts,
          schema_json: PromptRenderer.load_schema("loremaster"),
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
