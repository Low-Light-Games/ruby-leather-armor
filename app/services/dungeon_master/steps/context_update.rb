# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step 6a/6b: Context updates.
    # 6a — Micro context update (self-directed: reads outcome, decides which domains changed)
    # 6b — Macro narrative update (story summary)
    # Run in parallel; 6b is conditional on macro_significant.
    #
    # ContextUpdate is the sole writer of all Adventure context fields.
    # It receives what_happened (the full outcome text) and decides independently
    # which of the six domains to update. No upstream affected_contexts signal is
    # used — the AI reads the outcome and makes that judgment itself.
    module ContextUpdate
      private

      def run_context_updates(what_happened, mutations, macro_significant: false)
        broadcast_progress("Remembering the world...")
        micro_thread = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection { run_micro_context_update(what_happened, mutations) }
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
        handle_context_wishes(micro_result["context_wishes"]) if micro_result["context_wishes"].present?

        if macro_thread
          macro_result = macro_thread.value
          @adventure.update!(story_summary: macro_result["story_summary"]) if macro_result["story_summary"].present?
        end
      rescue => e
        pipeline_error!("context_updates", e)
      end

      def run_micro_context_update(what_happened, mutations)
        prompt_summary = "Micro context update"
        micro_contexts = PromptHelpers.all_micro_contexts(@adventure)

        context_schemas = PromptHelpers::CONTEXT_FIELDS.each_with_object({}) do |field, h|
          h[field] = PromptRenderer.load_schema("contexts/#{field}_context")
        end

        system_prompt, user_msg = PromptRenderer.render_with_user_message("micro_context_update",
          micro_contexts: micro_contexts,
          context_fields: PromptHelpers::CONTEXT_FIELDS,
          context_schemas: context_schemas,
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
        snapshot_contexts_to_loop
      end

      def snapshot_contexts_to_loop
        return unless @loop

        snapshot = PromptHelpers::CONTEXT_FIELDS.each_with_object({}) do |field, h|
          key = "#{field}_context"
          h[key] = @adventure.public_send(key)
        end

        @loop.batch_update!(new_data: { "context_snapshot" => snapshot })
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

      # Log context wishes emitted by the AI when the outcome touches something
      # that doesn't map cleanly to the existing six domain fields. These are
      # observability signals for future context domain design, visible in the
      # admin play log UI under event_type "context_wish".
      def handle_context_wishes(wishes)
        Array(wishes).each do |wish|
          next unless wish.is_a?(String) && wish.present?
          @log.play_log!("context_wish", wish)
        end
      end
    end
  end
end
