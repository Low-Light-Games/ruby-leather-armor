# frozen_string_literal: true

module DungeonMaster
  # Monolithic single-call pipeline for the AI Dungeon Master.
  #
  # Activated when pipeline_mode is "edge". Replaces the multi-step budget
  # pipeline with one large AI call that handles sanitization, intent,
  # mechanical adjudication (rolls simulated internally), narration, and
  # context updates all at once.
  #
  # Trade-offs vs. budget pipeline:
  #   + Lower latency (1 round-trip vs. 10+)
  #   + Simpler flow, fewer failure points
  #   - No roll requests — AI simulates dice internally
  #   - Less controllable per-step (no granular model/token overrides)
  #   - Harder to debug (single opaque call)
  #
  class EdgePipeline
    include Steps::Helpers
    include Mutations

    def initialize(adventure:, config:, ai:, log:, sheet:, on_progress: nil)
      @adventure   = adventure
      @config      = config
      @ai          = ai
      @log         = log
      @sheet       = sheet
      @on_progress = on_progress
    end

    def run_prompt(player_input, mode: nil)
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      raw = nil
      prompt_summary = "EdgePipeline: \"#{@log.truncate(player_input)}\""

      char_block = @sheet ? CharacterBlock.full(@sheet) : "(no character sheet)"
      micro_contexts = PromptHelpers.build_micro_contexts_block(@adventure)
      creature_stats = CharacterBlock.creature_stats_for(@adventure)
      story = build_story_block
      pacing = PromptHelpers.pacing_instructions(@config)
      directed = PromptHelpers.directed_play_instructions(@adventure)

      system_prompt = PromptRenderer.render("edge_pipeline",
        character_block: char_block,
        micro_contexts: micro_contexts,
        time_context: @adventure.time_context || {},
        creature_stats: creature_stats,
        story_block: story,
        pacing_text: pacing,
        directed_play_text: directed,
        dm_query_mode: mode == "dm_query")

      request_body = { system_prompt: system_prompt, user_message: player_input }
      raw = @ai.chat(
        system_prompt: system_prompt,
        user_message: player_input,
        max_tokens: @config.token_budget_for("edge_pipeline"),
        step_name: "edge_pipeline",
        model: @config.model_for("edge_pipeline"))

      parsed = @ai.parse_json(raw)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
      @log.ai_log!("edge_pipeline", prompt_summary, raw, parsed,
                   parse_status: @ai.last_parse_status, request_body: request_body,
                   model_used: @ai.last_model_used, duration_ms: duration_ms,
                   usage: @ai.last_usage)

      handle_result(parsed)
    rescue TokenBudgetExceededError => e
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
      @log.ai_log_error!("edge_pipeline", prompt_summary, e,
                         raw_response: raw || @ai.last_failed_raw_response,
                         request_body: request_body, status: "token_budget_exceeded",
                         model_used: @ai.last_model_used, duration_ms: duration_ms,
                         usage: @ai.last_usage)
      raise
    rescue AiError => e
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
      @log.ai_log_error!("edge_pipeline", prompt_summary, e,
                         raw_response: raw || @ai.last_failed_raw_response,
                         request_body: request_body, model_used: @ai.last_model_used,
                         duration_ms: duration_ms, usage: @ai.last_usage)
      raise
    end

    # Edge pipeline never pauses for rolls, so this is a no-op fallback
    # that re-runs the prompt. The service layer should not route here.
    def run_rolls(_roll_results, _metadata)
      raise AiError, "EdgePipeline does not support roll resumption — rolls are resolved internally"
    end

    private

    def build_story_block
      parts = []
      parts << "Title: #{@adventure.story.title}"
      parts << "Hook: #{@adventure.story.preview}" if @adventure.story.preview.present?
      atmosphere = @adventure.enriched_world&.dig("atmosphere")
      parts << "Atmosphere: #{atmosphere}" if atmosphere.present?
      parts << "Story so far: #{@adventure.story_summary}" if @adventure.story_summary.present?
      parts.join("\n")
    end

    def handle_result(parsed)
      if parsed["rejected"] == true
        @log.log!(:info, "Edge rejected: #{parsed['rejection_reason']}")
        return { action: :rejected, reason: parsed["rejection_reason"] || "Input rejected." }
      end

      if parsed["dm_answer"].present?
        return { action: :dm_query, answer: parsed["dm_answer"] }
      end

      apply_edge_mutations(parsed["mutations"]) if parsed["mutations"].present?
      apply_edge_time_update(parsed["time_update"]) if parsed["time_update"].present?
      persist_context_updates(parsed["context_updates"]) if parsed["context_updates"].present?
      persist_scene_summary(parsed["scene_summary"])
      update_story_summary(parsed["story_summary_update"]) if parsed["story_summary_update"].present?

      narrative = parsed["narrative"]
      raise AiError, "EdgePipeline returned no narrative" unless narrative.present?

      { action: :narrated, narrative: narrative,
        adventure_complete: parsed["adventure_complete"] == true }
    end

    def apply_edge_mutations(mutations)
      apply_mutations(mutations.deep_symbolize_keys)
    rescue => e
      pipeline_error!("edge_mutations", e)
    end

    def apply_edge_time_update(time_update)
      hours = (time_update["hours_elapsed"] || 0).to_f
      return if hours <= 0

      Utilities::GameClock.advance_clock!(@adventure, hours)
    rescue => e
      pipeline_error!("edge_time", e)
    end

    def persist_context_updates(updates)
      fields = PromptHelpers::CONTEXT_FIELDS
      attrs = fields.each_with_object({}) do |field, h|
        key = "#{field}_context"
        h[key.to_sym] = updates[key] if updates[key].present?
      end
      @adventure.update!(attrs) if attrs.any?
    rescue => e
      pipeline_error!("edge_context", e)
    end

    def persist_scene_summary(summary)
      @adventure.update!(scene_summary: summary) if summary.present?
    end

    def update_story_summary(summary)
      @adventure.update!(story_summary: summary)
    rescue => e
      pipeline_error!("edge_summary", e)
    end
  end
end
