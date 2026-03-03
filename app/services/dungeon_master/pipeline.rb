# frozen_string_literal: true

module DungeonMaster
  # Pure pipeline logic for the AI Dungeon Master.
  #
  # Runs steps in order and returns a result hash describing what happened.
  # Does NOT persist messages or handle errors -- the calling service
  # (DungeonMasterService) is responsible for those side effects.
  #
  # Flow:
  #   run_prompt  -> sanitize + classify (parallel) -> dm_query_flow | action_flow
  #   action_flow -> intent -> dispatchers (parallel) -> converge -> ruling | narrate
  #   run_rolls   -> resolution_flow  (resumption after player rolls)
  #
  class Pipeline
    PROMPT_CATEGORIES = %w[combat traversal social exploration rest inventory dm_query].freeze

    include Steps::Triage
    include Steps::DmQuery
    include Steps::Intent
    include Steps::InterpretationDispatcher
    include Steps::Ruling
    include Steps::Evaluate
    include Steps::Chronicler
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
        sanitize_result = run_sanitize(player_input)
        if sanitize_result[:danger_score] >= @config.sanitization_threshold
          @log.dm_log!("Rejected (danger: #{sanitize_result[:danger_score]}): #{sanitize_result[:reason]}")
          return { action: :rejected, reason: sanitize_result[:reason], danger: sanitize_result[:danger_score] }
        end
        return run_dm_query_flow(sanitize_result[:sanitized_input])
      end

      sanitize_result, classify_result = run_gate(player_input)

      if sanitize_result[:danger_score] >= @config.sanitization_threshold
        @log.dm_log!("Rejected (danger: #{sanitize_result[:danger_score]}): #{sanitize_result[:reason]}")
        return { action: :rejected, reason: sanitize_result[:reason], danger: sanitize_result[:danger_score] }
      end

      clean_input = sanitize_result[:sanitized_input]

      if classify_result[:category] == "dm_query"
        return run_dm_query_flow(clean_input)
      end

      run_action_flow(clean_input, classify_result[:category])
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
      intent_stub = { intention: clean_input, primary_context: "dm_query", affected_contexts: [], macro_significant: false, plot_relevant: true }
      plot_result = resolve_plot(intent_stub)
      dm_brief = plot_result&.dig(:dm_brief)

      result = run_dm_query(clean_input, dm_brief: dm_brief)
      { action: :dm_query, answer: result[:answer] }
    end

    def run_action_flow(clean_input, category = nil)
      intention = run_intent(clean_input)
      intent = run_dispatchers(intention, category)

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

      dm_brief = nil
      if intent[:plot_relevant]
        plot_result = resolve_plot(intent)
        dm_brief = plot_result&.dig(:dm_brief)
      end

      narration = run_narrate(nil, player_action: clean_input, intent: intent, dm_brief: dm_brief)
      run_context_updates(narration[:narrative], nil,
                          affected_contexts: intent[:affected_contexts],
                          macro_significant: intent[:macro_significant])
      { action: :narrated, narrative: narration[:narrative], adventure_complete: narration[:adventure_complete] }
    end

    def run_time_span_flow(intent, clean_input)
      if intent[:time_span_type] == "journey" && !Array(intent[:affected_contexts]).include?("traversal")
        intent[:affected_contexts] = (Array(intent[:affected_contexts]) + ["traversal"]).uniq
      end

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

      dm_brief = nil
      if intent[:plot_relevant]
        plot_result = resolve_plot(intent, evaluate_outcome: eval_result[:outcome])
        dm_brief = plot_result&.dig(:dm_brief)
      end

      narration = run_narrate(ts_result[:narrative_seed], player_action: nil, intent: intent, dm_brief: dm_brief)
      run_context_updates(narration[:narrative], ts_result[:mutations],
                          affected_contexts: intent[:affected_contexts],
                          macro_significant: intent[:macro_significant])
      { action: :narrated, narrative: narration[:narrative], adventure_complete: narration[:adventure_complete] }
    end

    def run_resolution_flow(intent, merged, roll_results)
      npc_results = resolve_npc_actions(merged[:npc_actions])
      eval_result = run_evaluate(intent, merged, roll_results: roll_results, npc_results: npc_results)
      apply_mutations(eval_result[:mutations])

      dm_brief = nil
      if intent[:plot_relevant]
        plot_result = resolve_plot(intent, evaluate_outcome: eval_result[:outcome])
        dm_brief = plot_result&.dig(:dm_brief)
      end

      narration = run_narrate(eval_result[:outcome], dm_brief: dm_brief)
      run_context_updates(narration[:narrative], eval_result[:mutations],
                          affected_contexts: intent[:affected_contexts],
                          macro_significant: intent[:macro_significant])
      { action: :narrated, narrative: narration[:narrative], adventure_complete: narration[:adventure_complete] }
    end

    # ----------------------------------------------------------------
    # Gate: parallel sanitize + classify
    # ----------------------------------------------------------------

    def run_gate(player_input)
      sanitize_result = classify_result = nil

      sanitize_thread = Thread.new { sanitize_result = run_sanitize(player_input) }
      classify_thread = Thread.new { classify_result = run_classify(player_input) }

      sanitize_thread.value
      classify_thread.value

      [sanitize_result, classify_result]
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

    def should_run_chronicler?
      return false if @config.get("skip_chronicler") == true
      has_structured_story_data?
    end

    def has_structured_story_data?
      StoryNpc.where(story_id: @adventure.story_id).exists? ||
        StoryClue.where(story_id: @adventure.story_id).exists?
    end

    # Runs the AI Chronicler if available, otherwise falls back to heuristic DC matching.
    def resolve_plot(intent, evaluate_outcome: nil)
      if should_run_chronicler?
        run_chronicler(intent, evaluate_outcome: evaluate_outcome)
      elsif has_structured_story_data?
        heuristic_chronicler(intent, evaluate_outcome: evaluate_outcome)
      end
    end

    # Deterministic DC-based clue matching fallback when the Chronicler AI is not available.
    # Checks each undiscovered clue against location, method, prerequisites, and difficulty.
    # Returns a hash shaped like Chronicler output (dm_brief, etc.).
    DC_MAP = { "automatic" => 0, "easy" => 10, "moderate" => 15, "hard" => 25 }.freeze
    METHOD_CONTEXT_MAP = {
      "social" => "social", "exploration" => "exploration",
      "magic" => "exploration", "combat" => "combat", "automatic" => nil,
    }.freeze

    def heuristic_chronicler(intent, evaluate_outcome: nil)
      plot_state = @adventure.plot_state || {}
      discovered_ids = plot_state["discovered_clues"] || []
      current_loc_id = @adventure.current_location_id

      all_clues = StoryClue.for_adventure(@adventure)
      undiscovered = all_clues.reject { |c| discovered_ids.include?(c.id) }

      revealed = []
      attempted = []

      undiscovered.each do |clue|
        next if clue.location_id && clue.location_id != current_loc_id

        expected_context = METHOD_CONTEXT_MAP[clue.discovery_method]
        next if expected_context && intent[:primary_context] != expected_context

        next if (clue.prerequisite_clue_ids || []).any? { |pid| !discovered_ids.include?(pid) }

        dc = DC_MAP[clue.difficulty] || 15
        if dc == 0
          revealed << clue
        else
          attempted << clue
        end
      end

      new_discovered = revealed.map(&:id)
      new_attempted  = attempted.map(&:id)

      if new_discovered.any? || new_attempted.any?
        ps = plot_state.deep_dup
        ps["discovered_clues"] = ((ps["discovered_clues"] || []) + new_discovered).uniq
        ps["attempted_clues"]  = ((ps["attempted_clues"] || []) + new_attempted).uniq
        @adventure.update!(plot_state: ps)
      end

      guidance_parts = []
      revealed.each { |c| guidance_parts << "The player discovers: #{c.title}" }
      guidance_parts << "Do NOT reveal any plot secrets beyond what was just discovered." if revealed.any?

      {
        dm_brief: guidance_parts.any? ? guidance_parts.join(". ") : nil,
        clues_revealed: revealed.map { |c| { "id" => c.id, "title" => c.title } },
        npc_reactions: {},
        atmosphere_notes: "",
        milestones_reached: [],
      }
    end

    def normalize_category(category)
      normalized = category.to_s.downcase.strip
      raise AiError, "Triage returned unrecognized category '#{category}' — expected one of: #{PROMPT_CATEGORIES.join(', ')}" unless PROMPT_CATEGORIES.include?(normalized)
      normalized
    end
  end
end
