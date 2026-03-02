# frozen_string_literal: true

module DungeonMaster
  # Pure pipeline logic for the AI Dungeon Master.
  #
  # Runs steps in order and returns a result hash describing what happened.
  # Does NOT persist messages or handle errors -- the calling service
  # (DungeonMasterService) is responsible for those side effects.
  #
  # Flow:
  #   run_prompt  -> triage -> dm_query_flow | action_flow
  #   run_rolls   -> resolution_flow  (resumption after player rolls)
  #
  class Pipeline
    PROMPT_CATEGORIES = %w[combat traversal social exploration rest inventory dm_query].freeze

    include Steps::Triage
    include Steps::DmQuery
    include Steps::Intent
    include Steps::Ruling
    include Steps::Evaluate
    include Steps::Narrate
    include Steps::ContextUpdate
    include Steps::TimeSpanResolver
    include Mutations

    def initialize(adventure:, config:, ai:, log:, sheet:)
      @adventure = adventure
      @config    = config
      @ai        = ai
      @log       = log
      @sheet     = sheet
    end

    # Main entry point: player typed something.
    # Returns a hash with :action key describing the outcome.
    # @param mode [String, nil] "dm_query" when the player explicitly toggled Ask DM mode
    def run_prompt(player_input, mode: nil)
      if mode == "dm_query"
        triage = run_sanitize_only(player_input)
        if triage[:danger_score] >= @config.sanitization_threshold
          @log.dm_log!("Rejected (danger: #{triage[:danger_score]}): #{triage[:reason]}")
          return { action: :rejected, reason: triage[:reason], danger: triage[:danger_score] }
        end
        return run_dm_query_flow(triage[:sanitized_input])
      end

      triage = run_triage(player_input)

      if triage[:danger_score] >= @config.sanitization_threshold
        @log.dm_log!("Rejected (danger: #{triage[:danger_score]}): #{triage[:reason]}")
        return { action: :rejected, reason: triage[:reason], danger: triage[:danger_score] }
      end

      clean_input = triage[:sanitized_input]

      if triage[:category] == "dm_query"
        return run_dm_query_flow(clean_input)
      end

      run_action_flow(clean_input)
    end

    # Resumption entry point: player submitted roll results.
    def run_rolls(roll_results, metadata)
      intent, merged = restore_from_metadata(metadata)

      if intent[:time_spanning]
        return run_time_span_resolution(intent, merged, roll_results)
      end

      run_resolution_flow(intent, merged, roll_results)
    end

    private

    # ----------------------------------------------------------------
    # Flow branches
    # ----------------------------------------------------------------

    def run_dm_query_flow(clean_input)
      result = run_dm_query(clean_input)
      { action: :dm_query, answer: result[:answer] }
    end

    def run_action_flow(clean_input)
      intent = run_intent(clean_input)

      if intent[:time_spanning]
        return run_time_span_flow(intent, clean_input)
      end

      if intent[:needs_mechanics]
        rulings = run_ruling_loop(intent)
        merged  = merge_rulings(rulings)

        if merged[:player_rolls].any?
          return { action: :awaiting_rolls, intent: intent, merged: merged }
        end

        return run_resolution_flow(intent, merged, "(no player rolls required)")
      end

      narration = run_narrate(nil, player_action: clean_input, intent: intent)
      run_context_updates(narration[:narrative], nil,
                          affected_contexts: intent[:affected_contexts],
                          macro_significant: intent[:macro_significant])
      { action: :narrated, narrative: narration[:narrative], adventure_complete: narration[:adventure_complete] }
    end

    def run_time_span_flow(intent, clean_input)
      rulings = run_ruling_loop(intent)
      merged  = merge_rulings(rulings)

      time_span_params = rulings.first&.dig(:time_span_parameters) || {}
      merged[:time_span_parameters] = time_span_params

      if merged[:player_rolls].any?
        return { action: :awaiting_rolls, intent: intent, merged: merged, time_spanning: true }
      end

      run_time_span_resolution(intent, merged, "(no player rolls required)")
    end

    def run_time_span_resolution(intent, merged, roll_results)
      npc_results = resolve_npc_actions(merged[:npc_actions])
      eval_result = run_evaluate(intent, merged, roll_results: roll_results, npc_results: npc_results)

      ts_result = run_time_span(intent, eval_result, merged)

      if ts_result[:stop_reason] == :encounter
        narration = run_narrate(ts_result[:narrative_seed], player_action: nil, intent: intent)
        partial_mutations = ts_result[:mutations]
        apply_time_span_mutations(partial_mutations)
        run_context_updates(narration[:narrative], partial_mutations,
                            affected_contexts: intent[:affected_contexts],
                            macro_significant: false)
        return { action: :narrated, narrative: narration[:narrative], adventure_complete: false,
                 time_span_interrupted: true }
      end

      apply_mutations(eval_result[:mutations])
      apply_time_span_mutations(ts_result[:mutations])

      narration = run_narrate(ts_result[:narrative_seed], player_action: nil, intent: intent)
      run_context_updates(narration[:narrative], ts_result[:mutations],
                          affected_contexts: intent[:affected_contexts],
                          macro_significant: intent[:macro_significant])
      { action: :narrated, narrative: narration[:narrative], adventure_complete: narration[:adventure_complete] }
    end

    def run_resolution_flow(intent, merged, roll_results)
      npc_results = resolve_npc_actions(merged[:npc_actions])
      eval_result = run_evaluate(intent, merged, roll_results: roll_results, npc_results: npc_results)
      apply_mutations(eval_result[:mutations])

      narration = run_narrate(eval_result[:outcome])
      run_context_updates(narration[:narrative], eval_result[:mutations],
                          affected_contexts: intent[:affected_contexts],
                          macro_significant: intent[:macro_significant])
      { action: :narrated, narrative: narration[:narrative], adventure_complete: narration[:adventure_complete] }
    end

    # ----------------------------------------------------------------
    # Helpers
    # ----------------------------------------------------------------

    def restore_from_metadata(metadata)
      intent = metadata["intent"]&.deep_symbolize_keys ||
               { intention: "continue", affected_contexts: [], macro_significant: false }
      ruling_summaries = metadata["ruling_summaries"] || []
      npc_actions  = (metadata["pending_npc_actions"]  || []).map(&:deep_symbolize_keys)
      consequences = (metadata["pending_consequences"] || []).map(&:deep_symbolize_keys)
      time_span_parameters = (metadata["time_span_parameters"] || {}).deep_symbolize_keys

      merged = {
        player_rolls: [], npc_actions: npc_actions,
        consequences: consequences, ruling_summaries: ruling_summaries,
        time_span_parameters: time_span_parameters
      }

      [intent, merged]
    end

    def normalize_category(category)
      normalized = category.to_s.downcase.strip
      raise AiError, "Triage returned unrecognized category '#{category}' — expected one of: #{PROMPT_CATEGORIES.join(', ')}" unless PROMPT_CATEGORIES.include?(normalized)
      normalized
    end
  end
end
