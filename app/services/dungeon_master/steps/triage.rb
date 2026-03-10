# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Gate: parallel Sanitize + Classify.
    #
    # Sanitize — scores danger (prompt injection / meta-gaming). Can kill the pipeline.
    # Classify — categorises the player's action into a game domain.
    #
    # These two steps have zero dependency on each other and run in parallel.
    module Triage
      private

      def run_sanitize(player_input)
        prompt_summary = "Sanitize: \"#{@log.truncate(player_input)}\""
        system_prompt = PromptRenderer.render("sanitize")
        request_body = { system_prompt: system_prompt, user_message: player_input }

        parsed = timed_ai_call("sanitize", prompt_summary, request_body) do
          raw = @ai.chat(system_prompt: system_prompt, user_message: player_input,
                          max_tokens: @config.token_budget_for("sanitize"), step_name: "sanitize",
                          model: @config.model_for("sanitize"))
          [raw, @ai.parse_json(raw, fallback_as: :sanitization)]
        end

        {
          danger_score: parsed["danger_score"].to_i,
          sanitized_input: parsed["sanitized_input"] || player_input,
          reason: parsed["reason"]
        }
      end

      def run_classify(player_input)
        prompt_summary = "Classify: \"#{@log.truncate(player_input)}\""
        system_prompt = PromptRenderer.render("classify")
        request_body = { system_prompt: system_prompt, user_message: player_input }

        parsed = timed_ai_call("classify", prompt_summary, request_body) do
          raw = @ai.chat(system_prompt: system_prompt, user_message: player_input,
                          max_tokens: @config.token_budget_for("classify"), step_name: "classify",
                          model: @config.model_for("classify"))
          [raw, @ai.parse_json(raw)]
        end

        {
          category: normalize_category(parsed["category"])
        }
      end
    end
  end
end
