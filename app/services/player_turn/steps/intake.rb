# frozen_string_literal: true

module PlayerTurn
  module Steps
    module Intake
      private

      def run_intake(player_input)
        prompt_summary = "Intake: \"#{@log.truncate(player_input)}\""
        system_prompt = Ai::PromptRenderer.render("intake")
        request_body = { system_prompt: system_prompt, user_message: player_input }

        parsed = timed_ai_call("intake", prompt_summary, request_body) do
          raw = @ai.chat(system_prompt: system_prompt, user_message: player_input,
                          step_name: "intake", model: @config.model_for("intake"))
          [raw, @ai.parse_json(raw)]
        end

        log_context_suggestion(parsed, player_input)

        raise Ai::Error, "Intake returned no sanitized_input — blocking pipeline" if parsed["sanitized_input"].blank?

        {
          danger_score: parsed["danger_score"].to_i,
          sanitized_input: parsed["sanitized_input"],
          reason: parsed["reason"]
        }
      end

      def log_context_suggestion(parsed, player_input)
        return unless parsed["suggested_context"].present?

        ExperienceSuggestion.create!(
          adventure: @adventure,
          registry_entry_uuid: @log.registry_entry_uuid,
          category: "new_context",
          source_step: "intake",
          details: {
            "context_name" => parsed["suggested_context"],
            "reason" => parsed["context_suggestion_reason"],
            "player_input" => player_input.truncate(500)
          }
        )
      rescue => e
        pipeline_error!("experience_suggestion", e)
      end
    end
  end
end
