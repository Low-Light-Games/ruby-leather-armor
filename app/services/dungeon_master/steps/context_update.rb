# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step 6a/6b: Context updates.
    # 6a — Micro context update (affected + active contexts only)
    # 6b — Macro narrative update (story summary)
    # Run in parallel; 6b is conditional on macro_significant.
    module ContextUpdate
      private

      def run_context_updates(what_happened, mutations, affected_contexts: [], macro_significant: false)
        micro_thread = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection { run_micro_context_update(what_happened, mutations, affected_contexts) }
        end
        macro_thread = if macro_significant
                         Thread.new do
                           ActiveRecord::Base.connection_pool.with_connection { run_macro_narrative_update(what_happened) }
                         end
                       end

        micro_result = micro_thread.value
        persist_micro_contexts(micro_result)
        persist_scene_summary(micro_result["scene_summary"])
        handle_new_creatures(micro_result["new_creatures"]) if micro_result["new_creatures"].present?

        if macro_thread
          macro_result = macro_thread.value
          @adventure.update!(story_summary: macro_result["story_summary"]) if macro_result["story_summary"].present?
        end
      rescue => e
        @log.dm_log!("Context update error: #{e.message}")
      end

      def run_micro_context_update(what_happened, mutations, affected_contexts)
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raw = nil
        prompt_summary = "Micro context update"
        micro_contexts = PromptHelpers.all_micro_contexts(@adventure)

        affected = Array(affected_contexts).map(&:to_s)
        active = PromptHelpers::CONTEXT_FIELDS.select { |f| micro_contexts[f.to_sym].present? }
        relevant = (affected | active).uniq & PromptHelpers::CONTEXT_FIELDS

        relevant = PromptHelpers::CONTEXT_FIELDS if relevant.empty?

        context_sections = relevant.map do |field|
          ctx = micro_contexts[field.to_sym]
          label = affected.include?(field) ? "#{field.upcase} CONTEXT [UPDATE]" : "#{field.upcase} CONTEXT [maintain]"
          "=== #{label} ===\n#{ctx.present? ? ctx.to_json : '{}'}"
        end

        system_prompt = PromptRenderer.render("micro_context_update",
          context_sections: context_sections.join("\n\n"),
          relevant_fields: relevant,
          affected_fields: affected,
          what_happened: what_happened,
          mutations_json: mutations.present? ? mutations.to_json : "(no mechanical mutations)",
          canonical_hp: build_canonical_hp)

        user_msg = "Update contexts based on the above."
        request_body = { system_prompt: system_prompt, user_message: user_msg }
        raw = @ai.chat(system_prompt: system_prompt, user_message: user_msg,
                        max_tokens: @config.token_budget_for("micro_context_update"),
                        step_name: "micro_context_update",
                        model: @config.model_for("micro_context_update"))
        parsed = @ai.parse_json(raw)
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        @log.ai_log!("micro_context_update", prompt_summary, raw, parsed,
                     parse_status: @ai.last_parse_status, request_body: request_body,
                     model_used: @ai.last_model_used, duration_ms: duration_ms,
                     usage: @ai.last_usage)
        parsed
      rescue TokenBudgetExceededError => e
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        @log.ai_log_error!("micro_context_update", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, status: "token_budget_exceeded",
                           model_used: @ai.last_model_used, duration_ms: duration_ms,
                           usage: @ai.last_usage)
        {}
      rescue AiError => e
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        @log.ai_log_error!("micro_context_update", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, model_used: @ai.last_model_used,
                           duration_ms: duration_ms,
                           usage: @ai.last_usage)
        {}
      end

      def run_macro_narrative_update(what_happened)
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raw = nil
        prompt_summary = "Macro narrative update"

        system_prompt = PromptRenderer.render("macro_narrative_update",
          story_intro: @adventure.story.hook.presence || @adventure.story.title,
          story_summary: @adventure.story_summary,
          what_happened: what_happened)

        user_msg = "Update the story summary."
        request_body = { system_prompt: system_prompt, user_message: user_msg }
        raw = @ai.chat(system_prompt: system_prompt, user_message: user_msg,
                        max_tokens: @config.token_budget_for("macro_narrative_update"),
                        step_name: "macro_narrative_update",
                        model: @config.model_for("macro_narrative_update"))
        parsed = @ai.parse_json(raw)
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        @log.ai_log!("macro_narrative_update", prompt_summary, raw, parsed,
                     parse_status: @ai.last_parse_status, request_body: request_body,
                     model_used: @ai.last_model_used, duration_ms: duration_ms,
                     usage: @ai.last_usage)
        parsed
      rescue TokenBudgetExceededError => e
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        @log.ai_log_error!("macro_narrative_update", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, status: "token_budget_exceeded",
                           model_used: @ai.last_model_used, duration_ms: duration_ms,
                           usage: @ai.last_usage)
        {}
      rescue AiError => e
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
        @log.ai_log_error!("macro_narrative_update", prompt_summary, e,
                           raw_response: raw || @ai.last_failed_raw_response,
                           request_body: request_body, model_used: @ai.last_model_used,
                           duration_ms: duration_ms,
                           usage: @ai.last_usage)
        {}
      end

      def persist_micro_contexts(parsed)
        updates = PromptHelpers::CONTEXT_FIELDS.each_with_object({}) do |field, h|
          key = "#{field}_context"
          h[key.to_sym] = parsed[key] if parsed[key].present?
        end
        @adventure.update!(updates) if updates.any?
      end

      def persist_scene_summary(summary)
        return unless summary.present?

        max_history = (@config.get("scene_history_depth") || 10).to_i
        history = Array(@adventure.scene_history)
        history.push({ "summary" => summary, "at" => Time.current.iso8601 })
        history = history.last(max_history)

        @adventure.update!(scene_summary: summary, scene_history: history)
      end

      def build_canonical_hp
        lines = []
        lines << "Player: #{@sheet.hp}/#{@sheet.max_hp}" if @sheet

        @adventure.creature_sheets.each do |c|
          lines << "#{c.name}: #{c.hp}/#{c.max_hp}"
        end

        lines.any? ? lines.join("\n") : nil
      end
    end
  end
end
