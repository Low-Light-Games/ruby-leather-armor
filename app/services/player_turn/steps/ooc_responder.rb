# frozen_string_literal: true

module PlayerTurn
  module Steps
    module OocResponder
      private

      def run_ooc_responder(clean_input)
        recent_messages = render_ooc_context
        combat_active = @adventure.combat_context&.dig("active") == true
        story_premise = @adventure.story&.premise.to_s.truncate(300).presence

        system_prompt = Ai::PromptRenderer.render("ooc_responder",
          recent_messages: recent_messages,
          combat_active: combat_active,
          story_premise: story_premise)

        prompt_summary = "OocResponder: \"#{@log.truncate(clean_input)}\""
        request_body = { system_prompt: system_prompt, user_message: clean_input }

        parsed = timed_ai_call("ooc_responder", prompt_summary, request_body) do
          raw = @ai.chat(system_prompt: system_prompt, user_message: clean_input,
                          step_name: "ooc_responder", model: @config.model_for("ooc_responder"),
                          reasoning_effort: @config.reasoning_effort_for("ooc_responder"))
          [raw, { "response" => raw }]
        end
        parsed["response"]
      end

      def render_ooc_context
        rows = Adventures::RecentMessages.dm_narration(@adventure)
        return "(no prior messages)" if rows.empty?

        rows.map { |c| c.to_s.truncate(280) }.join("\n\n")
      end
    end
  end
end
