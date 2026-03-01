# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step 6a/6b: Context updates.
    # 6a — Micro context update (traversal / combat / social)
    # 6b — Macro narrative update (story summary)
    # Run in parallel; 6b is conditional on macro_significant.
    module ContextUpdate
      private

      def run_context_updates(narrative, mutations, macro_significant: false)
        micro_thread = Thread.new { run_micro_context_update(narrative, mutations) }
        macro_thread = macro_significant ? Thread.new { run_macro_narrative_update(narrative) } : nil

        micro_result = micro_thread.value
        persist_micro_contexts(micro_result)
        handle_new_creatures(micro_result["new_creatures"]) if micro_result["new_creatures"].present?

        if macro_thread
          macro_result = macro_thread.value
          @adventure.update!(story_summary: macro_result["story_summary"]) if macro_result["story_summary"].present?
        end
      rescue => e
        @log.dm_log!("Context update error: #{e.message}")
      end

      def run_micro_context_update(narrative, mutations)
        raw = nil
        prompt_summary = "Micro context update"
        micro_contexts = {
          traversal: @adventure.traversal_context,
          combat: @adventure.combat_context,
          social: @adventure.social_context
        }

        system_prompt = PromptRenderer.render("micro_context_update",
          narrative: narrative,
          mutations_json: mutations.present? ? mutations.to_json : "(no mechanical mutations)",
          traversal_json: micro_contexts[:traversal].present? ? micro_contexts[:traversal].to_json : "{}",
          combat_json: micro_contexts[:combat].present? ? micro_contexts[:combat].to_json : "{}",
          social_json: micro_contexts[:social].present? ? micro_contexts[:social].to_json : "{}")

        user_msg = "Update contexts based on the above."
        request_body = { system_prompt: system_prompt, user_message: user_msg }
        raw = @ai.chat(system_prompt: system_prompt, user_message: user_msg,
                        max_tokens: @config.token_budget_for("micro_context_update"),
                        step_name: "micro_context_update",
                        model: @config.model_for("micro_context_update"))
        parsed = @ai.parse_json(raw)
        @log.ai_log!("micro_context_update", prompt_summary, raw, parsed,
                     parse_status: @ai.last_parse_status, request_body: request_body,
                     model_used: @ai.last_model_used)
        parsed
      rescue TokenBudgetExceededError => e
        @log.ai_log_error!("micro_context_update", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, status: "token_budget_exceeded",
                           model_used: @ai.last_model_used)
        {}
      rescue AiError => e
        @log.ai_log_error!("micro_context_update", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, model_used: @ai.last_model_used)
        {}
      end

      def run_macro_narrative_update(narrative)
        raw = nil
        prompt_summary = "Macro narrative update"

        system_prompt = PromptRenderer.render("macro_narrative_update",
          story_intro: @adventure.story.hook.presence || @adventure.story.title,
          story_summary: @adventure.story_summary,
          narrative: narrative)

        user_msg = "Update the story summary."
        request_body = { system_prompt: system_prompt, user_message: user_msg }
        raw = @ai.chat(system_prompt: system_prompt, user_message: user_msg,
                        max_tokens: @config.token_budget_for("macro_narrative_update"),
                        step_name: "macro_narrative_update",
                        model: @config.model_for("macro_narrative_update"))
        parsed = @ai.parse_json(raw)
        @log.ai_log!("macro_narrative_update", prompt_summary, raw, parsed,
                     parse_status: @ai.last_parse_status, request_body: request_body,
                     model_used: @ai.last_model_used)
        parsed
      rescue TokenBudgetExceededError => e
        @log.ai_log_error!("macro_narrative_update", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, status: "token_budget_exceeded",
                           model_used: @ai.last_model_used)
        {}
      rescue AiError => e
        @log.ai_log_error!("macro_narrative_update", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, model_used: @ai.last_model_used)
        {}
      end

      def persist_micro_contexts(parsed)
        updates = {}
        updates[:traversal_context] = parsed["traversal_context"] if parsed["traversal_context"].present?
        updates[:combat_context] = parsed["combat_context"] if parsed["combat_context"].present?
        updates[:social_context] = parsed["social_context"] if parsed["social_context"].present?
        @adventure.update!(updates) if updates.any?
      end
    end
  end
end
