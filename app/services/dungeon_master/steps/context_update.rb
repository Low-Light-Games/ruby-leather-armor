# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step 6a/6b: Context updates.
    # 6a — Micro context update (self-directed: reads outcome, decides which domains changed)
    # 6b — Macro narrative update (story summary)
    # Both are POSTed to Node /fan_out in a single call; 6b is conditional on macro_significant.
    #
    # ContextUpdate is the sole writer of all Adventure context fields.
    # It receives what_happened (the full outcome text) and decides independently
    # which of the six domains to update. No upstream affected_contexts signal is
    # used — the AI reads the outcome and makes that judgment itself.
    module ContextUpdate
      private

      def run_context_updates(what_happened, mutations, macro_significant: false)
        broadcast_progress("Remembering the world...")
        evaluator_url = ENV.fetch("EVALUATOR_URL", "http://evaluator:3001")

        prompts = build_context_update_prompts(what_happened, mutations, macro_significant: macro_significant)
        results = call_evaluator!("#{evaluator_url}/fan_out", prompts,
                                  what_happened.to_s.truncate(120), phase: "context_updates")

        apply_context_update_results(results, macro_significant: macro_significant)
      rescue => e
        pipeline_error!("context_updates", e)
      end

      # Builds the prompt array for a context-update fan-out call.
      # Called by run_context_updates and by Stagehand's run_parallel_narrative
      # (which merges these into the same fan-out as narrate).
      def build_context_update_prompts(what_happened, mutations, macro_significant: false)
        prompts = [build_micro_context_prompt(what_happened, mutations)]
        prompts << build_macro_narrative_prompt(what_happened) if macro_significant
        prompts
      end

      # Applies results from a context-update fan-out (called both here and from Stagehand).
      def apply_context_update_results(results, macro_significant: false)
        micro_raw = results.find { |r| r.dig("meta", "step") == "micro_context_update" }
        macro_raw = results.find { |r| r.dig("meta", "step") == "macro_narrative_update" }

        micro_result = micro_raw&.dig("parsed_response") || {}
        persist_micro_contexts(micro_result)
        persist_scene_summary(micro_result["scene_summary"])
        handle_new_creatures(micro_result["new_creatures"]) if micro_result["new_creatures"].present?
        handle_context_wishes(micro_result["context_wishes"]) if micro_result["context_wishes"].present?

        if macro_raw
          macro_result = macro_raw.dig("parsed_response") || {}
          @adventure.update!(story_summary: macro_result["story_summary"]) if macro_result["story_summary"].present?
        end
      end

      def build_micro_context_prompt(what_happened, mutations)
        micro_contexts   = PromptHelpers.all_micro_contexts(@adventure)
        context_schemas  = PromptHelpers::CONTEXT_FIELDS.each_with_object({}) do |field, h|
          h[field] = PromptRenderer.load_schema("contexts/#{field}_context")
        end

        system_prompt, user_msg = PromptRenderer.render_with_user_message("micro_context_update",
          micro_contexts:  micro_contexts,
          context_fields:  PromptHelpers::CONTEXT_FIELDS,
          context_schemas: context_schemas,
          what_happened:   what_happened,
          mutations_json:  mutations.present? ? mutations.to_json : nil,
          canonical_hp:    build_canonical_hp)

        {
          system_prompt: system_prompt,
          user_message:  user_msg,
          model:         @config.model_for("micro_context_update"),
          max_tokens:    @config.token_budget_for("micro_context_update"),
          meta:          { step: "micro_context_update" }
        }
      end

      def build_macro_narrative_prompt(what_happened)
        system_prompt, user_msg = PromptRenderer.render_with_user_message("macro_narrative_update",
          story_intro:    @adventure.story.preview,
          story_summary:  @adventure.story_summary,
          what_happened:  what_happened)

        {
          system_prompt: system_prompt,
          user_message:  user_msg,
          model:         @config.model_for("macro_narrative_update"),
          max_tokens:    @config.token_budget_for("macro_narrative_update"),
          meta:          { step: "macro_narrative_update" }
        }
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
