# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step 6a/6b: Context updates.
    # 6a — Micro context update: one parallel AI call per affected context,
    #      mirroring the beacon pattern. Each call is focused on a single domain.
    # 6b — Macro narrative update (story summary), conditional on macro_significant.
    module ContextUpdate
      private

      def run_context_updates(what_happened, mutations, affected_contexts: [], macro_significant: false, time_result: nil)
        affected = Array(affected_contexts).map(&:to_s)

        # Social must re-evaluate whenever traversal changes — a location change
        # may or may not end the current social scene, but the AI must decide.
        if affected.include?("traversal") && @adventure.social_context.present?
          affected = (affected | ["social"]).uniq
        end

        affected = PromptHelpers::CONTEXT_FIELDS if affected.empty?

        # Primary field drives scene_summary (highest-priority affected domain).
        primary_field = PromptHelpers::CONTEXT_FIELDS.find { |f| affected.include?(f) } || affected.first

        results = {}
        mutex = Mutex.new

        context_threads = affected.map do |field|
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              result = run_single_context_update(
                field, what_happened, mutations,
                time_result: time_result,
                primary: field == primary_field
              )
              mutex.synchronize { results[field] = result }
            end
          end
        end

        macro_thread = if macro_significant
                         Thread.new do
                           ActiveRecord::Base.connection_pool.with_connection { run_macro_narrative_update(what_happened) }
                         end
                       end

        context_threads.each(&:value)

        merged = results.values.each_with_object({}) { |r, h| h.merge!(r) }
        new_creatures = results.values.flat_map { |r| Array(r["new_creatures"]) }.uniq

        persist_micro_contexts(merged)
        handle_new_creatures(new_creatures) if new_creatures.present?

        scene_summary = results[primary_field]&.dig("scene_summary")
        persist_scene_summary(scene_summary) if scene_summary.present?

        if macro_thread
          macro_result = macro_thread.value
          @adventure.update!(story_summary: macro_result["story_summary"]) if macro_result["story_summary"].present?
        end
      rescue => e
        pipeline_error!("context_updates", e)
      end

      def run_single_context_update(field, what_happened, mutations, time_result: nil, primary: false)
        prompt_summary = "Micro context update [#{field}]#{primary ? ' + scene' : ''}"
        current_context = @adventure.send("#{field}_context")

        system_prompt, user_msg = PromptRenderer.render_with_user_message("micro_context_update",
          field: field,
          current_context: current_context,
          what_happened: what_happened,
          mutations_json: mutations.present? ? mutations.to_json : nil,
          canonical_hp: build_canonical_hp,
          time_result: time_result,
          primary: primary)

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
