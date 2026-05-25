# frozen_string_literal: true

module PlayerTurn
  module Steps
    module Interpreter
      STEP_NAME = "interpreter"

      private

      def interpreter_evaluator_prompt(action_text, original_input: nil)
        system_prompt = Ai::PromptRenderer.render(
          STEP_NAME,
          action_text: action_text.to_s,
          original_input: original_input.to_s,
          prior_resolved_actions: prior_resolved_action_texts,
          recent_conversation: render_recent_conversation_for_interpreter,
        )

        {
          system_prompt:    system_prompt,
          user_message:     action_text.to_s,
          model:            @config.model_for(STEP_NAME),
          reasoning_effort: @config.reasoning_effort_for(STEP_NAME),
          meta:             { step: STEP_NAME }
        }
      end

      def parse_interpreter_from_evaluator_result(result)
        parsed = result["parsed_response"] || {}
        text   = parsed["resolved_action_text"].to_s
        text.presence
      end

      def prior_resolved_action_texts
        return [] if @loop.nil? || @log&.registry_entry_uuid.blank?

        AdventureLoop
          .for_registry_entry(@log.registry_entry_uuid)
          .where("sequence_index < ?", @loop.sequence_index)
          .order(:sequence_index)
          .filter_map { |l| l.get("resolved_action_text") }
      end

      def render_recent_conversation_for_interpreter
        rows = Adventures::RecentMessages.conversation(@adventure)
        return nil if rows.empty?

        rows.map { |role, content| "#{role == 'player' ? 'Player' : 'DM'}: #{content.to_s.truncate(280)}" }.join("\n")
      end
    end
  end
end
