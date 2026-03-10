# frozen_string_literal: true

module DungeonMaster
  # Pure pipeline logic for the AI Dungeon Master.
  #
  # Runs steps in order and returns a result hash describing what happened.
  # Does NOT persist messages or handle errors -- the calling service
  # (DungeonMasterService) is responsible for those side effects.
  #
  # Flow:
  #   run_prompt          -> sanitize + classify (parallel) -> dm_query_flow | orchestrate_actions
  #   orchestrate_actions -> sequencer -> [ for each action: player_interpreter -> CoreResolver.resolve ] -> output_phase
  #   run_rolls           -> CoreResolver.finish_resolution -> continue queue if remaining -> output_phase
  #
  class Pipeline
    PROMPT_CATEGORIES = %w[combat traversal social exploration rest inventory dm_query].freeze

    include Steps::Helpers
    include Steps::Triage
    include Steps::DmQuery
    include Steps::PlayerInterpreter
    include Steps::Sequencer
    include Steps::Beacon
    include Steps::MechanicalEvaluation
    include Steps::RollQualifier
    include Steps::SanityChecker
    include Steps::UnifiedEvaluation
    include Steps::Verdict
    include Steps::TimeKeeper
    include Steps::Stagehand
    include Steps::Chronicler
    include Steps::Narrate
    include Steps::ContextUpdate
    include CoreResolver
    include Mutations

    def initialize(adventure:, config:, ai:, log:, sheet:)
      @adventure = adventure
      @config    = config
      @ai        = ai
      @log       = log
      @sheet     = sheet
      @loop      = nil
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

      orchestrate_actions(clean_input, classify_result[:category])
    end

    # Resumption entry point: player submitted initiative roll.
    def run_initiative(player_initiative, metadata)
      restore_paused_loop!
      @loop&.batch_update!(new_status: "resolved",
        timeline_entry: tl("initiative_resolved", "Player initiative: #{player_initiative}"))

      creature_data = metadata["creature_data"] || []
      Utilities::Warmaster.finalize_combat!(
        adventure: @adventure, creature_data: creature_data.map(&:deep_symbolize_keys),
        player_initiative: player_initiative)

      intent = metadata["intent"]&.deep_symbolize_keys || { intention: "combat", affected_contexts: ["combat"], macro_significant: false }
      narrate_seed = metadata["narrate_seed"]
      mutations = metadata["mutations"]
      remaining = metadata["remaining_actions"] || []
      prior_seeds = metadata["prior_narrate_seeds"] || []
      category = metadata["category"]

      if remaining.any?
        prior_seeds << narrate_seed if narrate_seed.present?
        run_remaining_queue(remaining, prior_seeds, category,
                            accumulated_intents: [intent],
                            accumulated_mutations: [mutations].compact)
      else
        run_accumulated_output_phase(
          [{ status: :encounter, intent: intent, narrate_seed: narrate_seed, mutations: mutations }],
          player_action: metadata["player_message_content"])
      end
    end

    # Resumption entry point: player submitted roll results.
    def run_rolls(roll_results, metadata)
      restore_paused_loop!
      tag_roll_resolution!(roll_results)

      intent, merged = restore_from_metadata(metadata)
      result = finish_resolution(intent, merged, roll_results)

      remaining   = metadata["remaining_actions"] || []
      prior_seeds = metadata["prior_narrate_seeds"] || []
      category    = metadata["category"]

      final_status = result[:status] == :encounter ? "encounter" : "resolved"
      @loop&.batch_update!(new_status: final_status,
        timeline_entry: tl("rolls_resolved", "Rolls submitted, status: #{final_status}"))

      if result[:status] == :resolved && remaining.any?
        prior_seeds << result[:narrate_seed]
        run_remaining_queue(remaining, prior_seeds, category,
                            accumulated_intents: [result[:intent]],
                            accumulated_mutations: [result[:mutations]])
      else
        run_accumulated_output_phase(
          [result], prior_seeds: prior_seeds,
          player_action: metadata["player_message_content"])
      end
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

    # Outer orchestrator: sequencer → action queue loop → output phase.
    def orchestrate_actions(clean_input, category = nil)
      actions = run_sequencer(clean_input)
      total = actions.size
      accumulated = []

      actions.each_with_index do |action_text, idx|
        set_action_label(idx, total)
        @loop = create_adventure_loop(action_text, idx)

        intention = run_player_interpreter(action_text)
        result = resolve(intention, category)

        case result[:status]
        when :rejected
          @loop&.batch_update!(new_status: "errored",
            timeline_entry: tl("rejected", result[:reason]))
          return { action: :rejected, reason: result[:reason] }

        when :awaiting_rolls
          @loop&.batch_update!(new_status: "paused",
            timeline_entry: tl("awaiting_rolls", "Paused for player rolls"))
          prior_seeds = accumulated.filter_map { |r| r[:narrate_seed] }
          remaining = actions[(idx + 1)..]
          log_queue_pause(idx, total, remaining)
          return {
            action: :awaiting_rolls, intent: result[:intent], merged: result[:merged],
            remaining_actions: remaining, prior_narrate_seeds: prior_seeds,
            category: category
          }

        when :awaiting_initiative
          @loop&.batch_update!(new_status: "paused",
            new_tags: { "combat_started" => true },
            timeline_entry: tl("awaiting_initiative", "Paused for player initiative"))
          prior_seeds = accumulated.filter_map { |r| r[:narrate_seed] }
          remaining = actions[(idx + 1)..]
          log_queue_pause(idx, total, remaining)
          return {
            action: :awaiting_initiative,
            intent: result[:intent],
            creature_data: result[:creature_data],
            narrate_seed: result[:narrate_seed],
            mutations: result[:mutations],
            remaining_actions: remaining,
            prior_narrate_seeds: prior_seeds,
            category: category
          }

        when :encounter
          @loop&.batch_update!(new_status: "encounter",
            timeline_entry: tl("encounter", "Encounter triggered"))
          accumulated << result
          log_queue_interrupt(idx, total, actions[(idx + 1)..])
          break

        when :resolved
          @loop&.batch_update!(new_status: "resolved",
            timeline_entry: tl("resolved", "Action resolved"))
          accumulated << result
        end
      end

      clear_action_label
      log_queue_completed(total) if total > 1

      run_accumulated_output_phase(accumulated, player_action: clean_input)
    end

    # Continue the action queue after a roll pause or from a mid-queue resume.
    def run_remaining_queue(remaining, prior_seeds, category,
                            accumulated_intents: [], accumulated_mutations: [])
      total_original = prior_seeds.size + remaining.size + 1
      base_idx = total_original - remaining.size
      accumulated = []

      remaining.each_with_index do |action_text, idx|
        action_idx = base_idx + idx
        set_action_label(action_idx, total_original)
        @loop = create_adventure_loop(action_text, action_idx)

        intention = run_player_interpreter(action_text)
        result = resolve(intention, category)

        case result[:status]
        when :rejected
          @loop&.batch_update!(new_status: "errored",
            timeline_entry: tl("rejected", result[:reason]))
          next

        when :awaiting_rolls
          @loop&.batch_update!(new_status: "paused",
            timeline_entry: tl("awaiting_rolls", "Paused for player rolls"))
          new_prior = prior_seeds + accumulated.filter_map { |r| r[:narrate_seed] }
          new_remaining = remaining[(idx + 1)..]
          log_queue_pause(action_idx, total_original, new_remaining)
          return {
            action: :awaiting_rolls, intent: result[:intent], merged: result[:merged],
            remaining_actions: new_remaining, prior_narrate_seeds: new_prior,
            category: category
          }

        when :awaiting_initiative
          @loop&.batch_update!(new_status: "paused",
            new_tags: { "combat_started" => true },
            timeline_entry: tl("awaiting_initiative", "Paused for player initiative"))
          new_prior = prior_seeds + accumulated.filter_map { |r| r[:narrate_seed] }
          new_remaining = remaining[(idx + 1)..]
          log_queue_pause(action_idx, total_original, new_remaining)
          return {
            action: :awaiting_initiative,
            intent: result[:intent],
            creature_data: result[:creature_data],
            narrate_seed: result[:narrate_seed],
            mutations: result[:mutations],
            remaining_actions: new_remaining,
            prior_narrate_seeds: new_prior,
            category: category
          }

        when :encounter
          @loop&.batch_update!(new_status: "encounter",
            timeline_entry: tl("encounter", "Encounter triggered"))
          accumulated << result
          log_queue_interrupt(action_idx, total_original, remaining[(idx + 1)..])
          break

        when :resolved
          @loop&.batch_update!(new_status: "resolved",
            timeline_entry: tl("resolved", "Action resolved"))
          accumulated << result
        end
      end

      clear_action_label
      run_accumulated_output_phase(accumulated, prior_seeds: prior_seeds)
    end

    # ----------------------------------------------------------------
    # Accumulated output phase
    # ----------------------------------------------------------------

    def run_accumulated_output_phase(results, prior_seeds: [], player_action: nil)
      return { action: :narrated, narrative: "", adventure_complete: false } if results.empty?

      merged_intent = merge_result_intents(results)
      all_seeds = prior_seeds + results.filter_map { |r| r[:narrate_seed] }
      all_mutations = results.filter_map { |r| r[:mutations] }
      encounter_triggered = results.any? { |r| r[:status] == :encounter }

      dm_brief = nil
      last_resolved = results.last
      if merged_intent[:plot_relevant]
        verdict_outcome = last_resolved[:narrate_seed]
        plot_result = resolve_plot(merged_intent, verdict_outcome: verdict_outcome,
                                   encounter_triggered: encounter_triggered)
        dm_brief = plot_result&.dig(:dm_brief)
      end

      combined_seed = all_seeds.compact.join("\n\nThen: ") if all_seeds.any?
      combined_mutations = all_mutations.compact.reduce({}) { |acc, m| deep_merge_mutations(acc, m) }

      extra = {}
      extra[:encounter_triggered] = true if encounter_triggered

      output_result = run_output_phase(merged_intent,
        narrate_seed: combined_seed,
        mutations: combined_mutations.presence,
        dm_brief: dm_brief,
        player_action: combined_seed.blank? ? player_action : nil,
        extra: extra)

      if output_result[:action] == :awaiting_initiative
        return output_result
      end

      output_result
    end

    def merge_result_intents(results)
      intents = results.map { |r| r[:intent] }.compact
      return intents.first if intents.size <= 1

      {
        intention: intents.map { |i| i[:intention] }.compact.join("; "),
        affected_contexts: intents.flat_map { |i| Array(i[:affected_contexts]) }.uniq,
        macro_significant: intents.any? { |i| i[:macro_significant] },
        plot_relevant: intents.any? { |i| i[:plot_relevant] },
        primary_context: intents.last[:primary_context],
        beacon_results: intents.last[:beacon_results]
      }
    end

    def deep_merge_mutations(base, overlay)
      return overlay if base.blank?
      return base if overlay.blank?
      base.deep_merge(overlay)
    end

    # ----------------------------------------------------------------
    # Gate: parallel sanitize + classify
    # ----------------------------------------------------------------

    def run_gate(player_input)
      sanitize_result = classify_result = nil

      sanitize_thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { sanitize_result = run_sanitize(player_input) }
      end
      classify_thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { classify_result = run_classify(player_input) }
      end

      sanitize_thread.value
      classify_thread.value

      [sanitize_result, classify_result]
    end

    # ----------------------------------------------------------------
    # Gate: parallel mechanical_evaluation + capability_check + world_consistency_check
    # ----------------------------------------------------------------

    def run_full_gate(intent)
      evaluations = nil
      world = nil
      capability = nil

      eval_thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { evaluations = run_mechanical_evaluation_loop(intent) }
      end
      world_thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { world = run_world_consistency_check(intent) }
      end
      cap_thread = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { capability = run_capability_check(intent) }
      end

      eval_thread.value
      world_thread.value
      cap_thread.value

      [evaluations, world, capability]
    end

    # ----------------------------------------------------------------
    # Helpers
    # ----------------------------------------------------------------

    def restore_from_metadata(metadata)
      intent = metadata["intent"]&.deep_symbolize_keys ||
               { intention: "continue", affected_contexts: [], macro_significant: false }
      mechanical_summaries = metadata["mechanical_summaries"] || metadata["ruling_summaries"] || []
      npc_actions  = (metadata["pending_npc_actions"]  || []).map(&:deep_symbolize_keys)
      consequences = (metadata["pending_consequences"] || []).map(&:deep_symbolize_keys)

      merged = {
        player_rolls: [], npc_actions: npc_actions,
        consequences: consequences, mechanical_summaries: mechanical_summaries
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
    def resolve_plot(intent, verdict_outcome: nil, encounter_triggered: false)
      if should_run_chronicler?
        run_chronicler(intent, verdict_outcome: verdict_outcome, encounter_triggered: encounter_triggered)
      elsif has_structured_story_data?
        heuristic_chronicler(intent, verdict_outcome: verdict_outcome)
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

    def heuristic_chronicler(intent, verdict_outcome: nil)
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

    # ----------------------------------------------------------------
    # Cross-domain roll deduplication
    # ----------------------------------------------------------------

    def deduplicate_rolls!(merged)
      seen = {}
      removed = []
      merged[:player_rolls] = merged[:player_rolls].select do |roll|
        key = [roll[:skill].to_s.downcase, roll[:type].to_s, roll[:dc].to_i]
        if seen[key]
          removed << "#{roll[:skill]} DC #{roll[:dc]} (#{roll[:domain]}) — duplicate of #{seen[key]}"
          false
        else
          seen[key] = roll[:domain] || "unknown"
          true
        end
      end
      @log.dm_log!("Dedup removed #{removed.size} duplicate roll(s): #{removed.join('; ')}") if removed.any?
    end

    # ----------------------------------------------------------------
    # Auto-success filter: removes rolls guaranteed to succeed
    # ----------------------------------------------------------------

    def filter_auto_success_rolls!(merged)
      skills_lookup = build_skills_lookup
      removed = []
      warned = []

      merged[:player_rolls] = merged[:player_rolls].reject do |roll|
        if roll[:type].to_s == "attack_roll"
          next false
        end

        raw_dc = roll[:dc]
        unless numeric_dc?(raw_dc)
          warned << "#{roll[:skill] || roll[:type]} has non-numeric DC '#{raw_dc}' — keeping roll"
          next false
        end

        dc = raw_dc.to_i
        reason = auto_success_reason(roll, dc, skills_lookup)
        if reason
          removed << "#{roll[:skill] || roll[:type]} DC #{dc}: #{reason}"
          true
        end
      end

      @log.dm_log!("Auto-success filter warning: #{warned.join('; ')}") if warned.any?
      @log.dm_log!("Auto-success filter removed #{removed.size} roll(s): #{removed.join('; ')}") if removed.any?
    end

    def auto_success_reason(roll, dc, skills_lookup)
      return "DC <= 0 (impossible to fail)" if dc <= 0

      if roll[:type].to_s == "skill_check"
        modifier = skills_lookup[roll[:skill].to_s]
        if modifier && (modifier + 1) >= dc
          return "modifier #{modifier} guarantees success (min roll 1 + #{modifier} = #{modifier + 1} >= DC #{dc})"
        end

        if roll[:take_10_eligible] && roll[:take_10_value].to_i >= dc
          return "Take 10 auto-succeeds (#{roll[:take_10_value]} >= DC #{dc})"
        end
      end

      nil
    end

    def numeric_dc?(value)
      value.is_a?(Integer) || (value.is_a?(String) && value.match?(/\A\d+\z/))
    end

    def build_skills_lookup
      return {} unless @sheet&.derived_stats.is_a?(Hash)

      Array(@sheet.derived_stats["skills"]).each_with_object({}) do |skill, h|
        h[skill["name"].to_s] = skill["total"].to_i if skill["name"].present?
      end
    end

    def normalize_category(category)
      normalized = category.to_s.downcase.strip
      raise AiError, "Triage returned unrecognized category '#{category}' — expected one of: #{PROMPT_CATEGORIES.join(', ')}" unless PROMPT_CATEGORIES.include?(normalized)
      normalized
    end

    # ----------------------------------------------------------------
    # Action label helpers (for queue index annotation in logs)
    # ----------------------------------------------------------------

    def set_action_label(idx, total)
      @log.action_label = total > 1 ? "[action #{idx + 1}/#{total}]" : nil
    end

    def clear_action_label
      @log.action_label = nil
    end

    # ----------------------------------------------------------------
    # Queue lifecycle logging
    # ----------------------------------------------------------------

    def log_queue_pause(idx, total, remaining)
      return unless total > 1
      @log.dm_log!("Action queue paused at action #{idx + 1}/#{total} (awaiting rolls). Remaining: #{remaining.inspect}")
    end

    def log_queue_interrupt(idx, total, remaining)
      return unless total > 1
      @log.dm_log!("Action queue interrupted at action #{idx + 1}/#{total} (encounter). Aborted: #{remaining.inspect}")
    end

    def log_queue_completed(total)
      @log.dm_log!("Action queue completed: #{total}/#{total} actions resolved")
    end

    # ----------------------------------------------------------------
    # AdventureLoop lifecycle helpers
    # ----------------------------------------------------------------

    def create_adventure_loop(action_text, sequence_index)
      AdventureLoop.create!(
        adventure: @adventure,
        pipeline_run_id: @log.pipeline_run_id,
        sequence_index: sequence_index,
        raw_action: action_text&.truncate(500),
        status: "pending"
      )
    rescue => e
      @log.dm_log!("AdventureLoop creation failed: #{e.message}")
      nil
    end

    def restore_paused_loop!
      return unless @log.pipeline_run_id
      @loop = AdventureLoop.for_pipeline(@log.pipeline_run_id).paused.order(:created_at).last
    end

    def tag_roll_resolution!(roll_results)
      return unless @loop

      text = roll_results.to_s.downcase
      if text.include?("take 20")
        @loop.batch_update!(
          new_tags: { "took_20" => true },
          new_data: { "resolution_method" => "take_20", "roll_results" => roll_results.to_s.truncate(500) })
      elsif text.include?("take 10")
        @loop.batch_update!(
          new_tags: { "took_10" => true },
          new_data: { "resolution_method" => "take_10", "roll_results" => roll_results.to_s.truncate(500) })
      else
        @loop.batch_update!(
          new_tags: { "rolled" => true },
          new_data: { "resolution_method" => "roll", "roll_results" => roll_results.to_s.truncate(500) })
      end
    end

    def tl(step, summary)
      { "step" => step.to_s, "summary" => summary.to_s.truncate(200), "at" => Time.current.iso8601 }
    end
  end
end
