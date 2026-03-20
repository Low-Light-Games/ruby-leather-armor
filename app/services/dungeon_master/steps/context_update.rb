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
        pipeline_error!("context_updates", e)
      end

      def run_micro_context_update(what_happened, mutations, affected_contexts)
        prompt_summary = "Micro context update"
        micro_contexts = PromptHelpers.all_micro_contexts(@adventure)

        affected = Array(affected_contexts).map(&:to_s)

        # When traversal is being updated, social must also be actively re-evaluated.
        # A location change may or may not end the current social scene — that is AI judgment —
        # but the AI must evaluate it rather than silently carrying the old scene forward.
        if affected.include?("traversal") && micro_contexts[:social].present?
          affected = (affected | ["social"]).uniq
        end

        active = PromptHelpers::CONTEXT_FIELDS.select { |f| micro_contexts[f.to_sym].present? }
        relevant = (affected | active).uniq & PromptHelpers::CONTEXT_FIELDS

        relevant = PromptHelpers::CONTEXT_FIELDS if relevant.empty?

        system_prompt, user_msg = PromptRenderer.render_with_user_message("micro_context_update",
          micro_contexts: micro_contexts,
          relevant_fields: relevant,
          affected_fields: affected,
          what_happened: what_happened,
          mutations_json: mutations.present? ? mutations.to_json : nil,
          canonical_hp: build_canonical_hp)

        request_body = { system_prompt: system_prompt, user_message: user_msg }

        timed_ai_call("micro_context_update", prompt_summary, request_body) do
          raw = @ai.chat(system_prompt: system_prompt, user_message: user_msg,
                          max_tokens: @config.token_budget_for("micro_context_update"),
                          step_name: "micro_context_update",
                          model: @config.model_for("micro_context_update"))
          [raw, @ai.parse_json(raw)]
        end
      end

      def run_macro_narrative_update(what_happened)
        prompt_summary = "Macro narrative update"

        system_prompt, user_msg = PromptRenderer.render_with_user_message("macro_narrative_update",
          story_intro: @adventure.story.hook.presence || @adventure.story.title,
          story_summary: @adventure.story_summary,
          what_happened: what_happened)

        request_body = { system_prompt: system_prompt, user_message: user_msg }

        timed_ai_call("macro_narrative_update", prompt_summary, request_body) do
          raw = @ai.chat(system_prompt: system_prompt, user_message: user_msg,
                          max_tokens: @config.token_budget_for("macro_narrative_update"),
                          step_name: "macro_narrative_update",
                          model: @config.model_for("macro_narrative_update"))
          [raw, @ai.parse_json(raw)]
        end
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
