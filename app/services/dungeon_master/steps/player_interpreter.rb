# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step: PlayerInterpreter (pure intent interpretation).
    # Restates what the player wants to do — nothing else.
    # No context classification, no mechanics decision, no rules.
    module PlayerInterpreter
      private

      def run_player_interpreter(sanitized_input)
        prompt_summary = "PlayerInterpreter: \"#{@log.truncate(sanitized_input)}\""
        system_prompt = PromptRenderer.render("player_interpreter")
        request_body = { system_prompt: system_prompt, user_message: sanitized_input }

        parsed = timed_ai_call("player_interpreter", prompt_summary, request_body) do
          raw = @ai.chat(system_prompt: system_prompt, user_message: sanitized_input,
                          max_tokens: @config.token_budget_for("player_interpreter"), step_name: "player_interpreter",
                          model: @config.model_for("player_interpreter"))
          [raw, @ai.parse_json(raw)]
        end

        intention = parsed["intention"] || sanitized_input
        @loop&.batch_update!(
          new_data: { "player_intent" => intention.to_s.truncate(500) },
          timeline_entry: { "step" => "player_interpreter", "summary" => "Intent: #{intention.to_s.truncate(120)}", "at" => Time.current.iso8601 })
        @loop&.update_column(:player_intent, intention.to_s.truncate(500)) if @loop
        intention
      end
    end
  end
end
