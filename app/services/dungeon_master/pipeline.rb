# frozen_string_literal: true

module DungeonMaster
  # Pure pipeline logic for the AI Dungeon Master.
  #
  # Runs steps in order and returns a result hash describing what happened.
  # Does NOT persist messages or handle errors -- the calling service
  # (DungeonMasterService) is responsible for those side effects.
  #
  # Flow:
  #   run_prompt          -> intake -> dm_query_flow | orchestrate_actions
  #   orchestrate_actions -> sequencer -> [ for each action: CoreResolver.resolve ] -> output_phase
  #                          output_phase: per-action narrative streamed immediately (action_queue setting)
  #                            "progressive"             — no prior context injected
  #                            "progressive_continuity"  — prior action outcomes fed into beacon/mech_eval/narrate
  #   run_rolls           -> CoreResolver.finish_resolution -> continue queue if remaining -> output_phase
  #
  class Pipeline
    include Steps::Helpers
    include Steps::NodeEvaluator
    include Steps::Intake
    include Steps::DmQuery
    include Steps::Sequencer
    include Steps::MechanicalEvaluation
    include Steps::SanityChecker
    include Steps::ParallelEvaluation
    include Steps::Mechanic
    include Steps::Momentum
    include Steps::TimeKeeper
    include Steps::Stagehand
    include Steps::Chronicler
    include Steps::Narrate
    include Steps::ContextUpdate
    include CoreResolver
    include Mutations

    def initialize(adventure:, config:, ai:, log:, sheet:, on_progress: nil, on_sheet_update: nil, on_narrative: nil)
      @adventure        = adventure
      @config           = config
      @ai               = ai
      @log              = log
      @sheet            = sheet
      @loop             = nil
      @on_progress      = on_progress
      @on_sheet_update  = on_sheet_update
      @on_narrative     = on_narrative
    end

    # Main entry point: player typed something.
    # Returns a hash with :action key describing the outcome.
    # @param mode [String, nil] "dm_query" when the player explicitly toggled Ask DM mode
    def run_prompt(player_input, mode: nil)
      intake_result = run_intake(player_input)

      if intake_result[:danger_score] >= @config.danger_threshold
        @log.play_log!("intake_rejection", "Rejected (danger: #{intake_result[:danger_score]}): #{intake_result[:reason]}")
        return { action: :rejected, reason: intake_result[:reason], danger: intake_result[:danger_score] }
      end

      clean_input = intake_result[:sanitized_input]

      if mode == "dm_query" || intake_result[:is_dm_query]
        return run_dm_query_flow(clean_input)
      end

      orchestrate_actions(clean_input)
    end

    # Resumption entry point: player submitted initiative roll.
    def run_initiative(player_initiative, metadata)
      restore_paused_loop!
      @loop&.batch_update!(new_status: "resolved",
        timeline_entry: tl("initiative_resolved", "Player initiative: #{player_initiative}"))

      creature_data = metadata["creature_data"] || []
      combat_data = Utilities::Warmaster.compute_combat_initialization(
        creature_data: creature_data.map(&:deep_symbolize_keys),
        player_initiative: player_initiative)

      intent = metadata["intent"]&.deep_symbolize_keys
      raise AiError, "Initiative metadata missing intent — state integrity failure" unless intent
      base_mutations = metadata["mutations"] || {}
      mutations = base_mutations.merge("combat_initialization" => combat_data)
      remaining = metadata["remaining_actions"] || []

      if remaining.any?
        run_remaining_queue(remaining,
                            accumulated_intents: [intent],
                            accumulated_mutations: [mutations].compact)
      else
        run_accumulated_narrative_phase(
          [{ status: :encounter, intent: intent, mutations: mutations }])
      end
    end

    # Resumption entry point: player submitted roll results.
    def run_rolls(roll_results, metadata)
      restore_paused_loop!
      tag_roll_resolution!(roll_results)

      intent, merged = restore_from_metadata(metadata)
      result = finish_resolution(intent, merged, roll_results)

      remaining = metadata["remaining_actions"] || []

      final_status = result[:status] == :encounter ? "encounter" : "resolved"
      @loop&.batch_update!(new_status: final_status,
        timeline_entry: tl("rolls_resolved", "Rolls submitted, status: #{final_status}"))

      if result[:status] == :resolved && remaining.any?
        run_remaining_queue(remaining,
                            accumulated_intents: [result[:intent]],
                            accumulated_mutations: [result[:mutations]])
      else
        run_accumulated_narrative_phase([result])
      end
    end

    private

    # ----------------------------------------------------------------
    # Flow branches
    # ----------------------------------------------------------------

    def run_dm_query_flow(clean_input)
      intent_stub = { intention: clean_input, affected_contexts: [], macro_significant: false }
      plot_result = resolve_plot(intent_stub)
      dm_brief = plot_result&.dig(:dm_brief)
      forbidden_elements = plot_result&.dig(:forbidden_elements) || []

      result = run_dm_query(clean_input, dm_brief: dm_brief, forbidden_elements: forbidden_elements)
      { action: :dm_query, answer: result[:answer] }
    end

    # Outer orchestrator: sequencer → action queue loop → output phase.
    def orchestrate_actions(clean_input)
      actions = run_sequencer(clean_input)
      total = actions.size
      accumulated = []
      use_per_action = per_action_narration? && total > 1
      action_narratives = []

      actions.each_with_index do |action_text, idx|
        set_action_label(idx, total)
        @loop = create_adventure_loop(action_text, idx)
        result = resolve(action_text)

        case result[:status]
        when :rejected
          @loop&.batch_update!(new_status: "errored",
            timeline_entry: tl("rejected", result[:reason]))
          return { action: :rejected, reason: result[:reason], dm_message: result[:dm_message] }

        when :awaiting_rolls
          @loop&.batch_update!(new_status: "paused",
            timeline_entry: tl("awaiting_rolls", "Paused for player rolls"))
          run_context_updates_at_pause(result[:intent], result[:merged])
          remaining = actions[(idx + 1)..]
          log_queue_pause(idx, total, remaining)
          return {
            action: :awaiting_rolls, intent: result[:intent], merged: result[:merged],
            remaining_actions: remaining
          }

        when :awaiting_initiative
          @loop&.batch_update!(new_status: "paused",
            new_tags: { "combat_started" => true },
            timeline_entry: tl("awaiting_initiative", "Paused for player initiative"))
          run_context_updates_at_encounter_pause(result[:mutations])
          remaining = actions[(idx + 1)..]
          log_queue_pause(idx, total, remaining)
          return {
            action: :awaiting_initiative,
            intent: result[:intent],
            creature_data: result[:creature_data],
            mutations: result[:mutations],
            remaining_actions: remaining
          }

        when :encounter
          @loop&.batch_update!(new_status: "encounter",
            timeline_entry: tl("encounter", "Encounter triggered"))
          accumulated << result
          log_queue_interrupt(idx, total, actions[(idx + 1)..], reason: "encounter")
          break

        when :social_scene
          @loop&.batch_update!(new_status: "social_scene",
            timeline_entry: tl("social_scene", "Social scene triggered"))
          accumulated << result
          log_queue_interrupt(idx, total, actions[(idx + 1)..], reason: "social_scene")
          break

        when :resolved
          @loop&.batch_update!(new_status: "resolved",
            timeline_entry: tl("resolved", "Action resolved"))
          if use_per_action
            action_narratives << run_single_action_narrative_phase(result, idx, total)
            run_inter_action_context_update(result) if idx < actions.size - 1
          else
            accumulated << result
            run_inter_action_context_update(result) if idx < actions.size - 1
          end
        end
      end

      clear_action_label
      log_queue_completed(total) if total > 1

      if use_per_action && action_narratives.any?
        if accumulated.any?
          # An encounter or social scene broke the loop after some resolved actions.
          # Narrate the encounter via the accumulated path; if it needs initiative
          # that takes priority and the per-action narratives are discarded.
          final = run_accumulated_narrative_phase(accumulated)
          return final unless final[:action] == :narrated
          action_narratives << {
            narrative: final[:narrative],
            adventure_complete: final[:adventure_complete],
            sequence_index: action_narratives.size,
            total_actions: total,
            action_text: nil
          }
        end
        { action: :narrated_sequence, narratives: action_narratives }
      else
        run_accumulated_narrative_phase(accumulated)
      end
    end

    # Continue the action queue after a roll pause or from a mid-queue resume.
    def run_remaining_queue(remaining, accumulated_intents: [], accumulated_mutations: [])
      processed_count = AdventureLoop.for_pipeline(@log.pipeline_run_id).count
      total_original = processed_count + remaining.size
      base_idx = processed_count
      accumulated = []

      remaining.each_with_index do |action_text, idx|
        action_idx = base_idx + idx
        set_action_label(action_idx, total_original)
        @loop = create_adventure_loop(action_text, action_idx)
        result = resolve(action_text)

        case result[:status]
        when :rejected
          @loop&.batch_update!(new_status: "errored",
            timeline_entry: tl("rejected", result[:reason]))
          next

        when :awaiting_rolls
          @loop&.batch_update!(new_status: "paused",
            timeline_entry: tl("awaiting_rolls", "Paused for player rolls"))
          run_context_updates_at_pause(result[:intent], result[:merged])
          new_remaining = remaining[(idx + 1)..]
          log_queue_pause(action_idx, total_original, new_remaining)
          return {
            action: :awaiting_rolls, intent: result[:intent], merged: result[:merged],
            remaining_actions: new_remaining
          }

        when :awaiting_initiative
          @loop&.batch_update!(new_status: "paused",
            new_tags: { "combat_started" => true },
            timeline_entry: tl("awaiting_initiative", "Paused for player initiative"))
          run_context_updates_at_encounter_pause(result[:mutations])
          new_remaining = remaining[(idx + 1)..]
          log_queue_pause(action_idx, total_original, new_remaining)
          return {
            action: :awaiting_initiative,
            intent: result[:intent],
            creature_data: result[:creature_data],
            mutations: result[:mutations],
            remaining_actions: new_remaining
          }

        when :encounter
          @loop&.batch_update!(new_status: "encounter",
            timeline_entry: tl("encounter", "Encounter triggered"))
          accumulated << result
          log_queue_interrupt(action_idx, total_original, remaining[(idx + 1)..], reason: "encounter")
          break

        when :social_scene
          @loop&.batch_update!(new_status: "social_scene",
            timeline_entry: tl("social_scene", "Social scene triggered"))
          accumulated << result
          log_queue_interrupt(action_idx, total_original, remaining[(idx + 1)..], reason: "social_scene")
          break

        when :resolved
          @loop&.batch_update!(new_status: "resolved",
            timeline_entry: tl("resolved", "Action resolved"))
          accumulated << result
          run_inter_action_context_update(result) if idx < remaining.size - 1
        end
      end

      clear_action_label
      run_accumulated_narrative_phase(accumulated)
    end

    # ----------------------------------------------------------------
    # Narrative phase (formerly output phase)
    # ----------------------------------------------------------------

    def run_accumulated_narrative_phase(results)
      return { action: :narrated, narrative: "", adventure_complete: false } if results.empty?

      merged_intent = merge_result_intents(results)
      all_loops = AdventureLoop.for_pipeline(@log.pipeline_run_id).order(:sequence_index)
      all_outcomes = all_loops.filter_map { |l| l.get("pipeline_outcome") }
      all_mutations = results.filter_map { |r| r[:mutations] }
      encounter_triggered = results.any? { |r| r[:status] == :encounter }
      social_scene_triggered = results.any? { |r| r[:status] == :social_scene }

      combined_seed = all_outcomes.compact.join("\n\nThen: ").presence
      combined_mutations = all_mutations.compact.reduce({}) { |acc, m| deep_merge_mutations(acc, m) }

      plot_result = resolve_plot(merged_intent, verdict_outcome: combined_seed,
                                 encounter_triggered: encounter_triggered)

      pipeline = PipelineContext.new(
        combined_seed: combined_seed,
        dm_brief: plot_result&.dig(:dm_brief),
        player_action: all_loops.filter_map(&:player_intent).join("\nThen: ").presence
      )

      extra = {}
      extra[:encounter_triggered] = true if encounter_triggered
      extra[:social_scene_triggered] = true if social_scene_triggered

      run_narrative_phase(merged_intent,
        pipeline: pipeline,
        mutations: combined_mutations.presence,
        extra: extra)
    end

    # Narrate a single resolved action immediately, before the next action starts.
    # Because loops are created one at a time, only this loop's pipeline_outcome
    # exists in the DB at this point, so the PipelineContext naturally carries
    # just the current action's outcome as its combined_seed.
    def run_single_action_narrative_phase(result, sequence_index, total_actions)
      outcome = @loop&.get("pipeline_outcome")
      plot_result = resolve_plot(result[:intent], verdict_outcome: outcome)

      action_pipeline = PipelineContext.new(
        combined_seed:  outcome,
        dm_brief:       plot_result&.dig(:dm_brief),
        player_action:  @loop&.player_intent,
        prior_outcomes: action_queue_continuity? ? prior_action_outcomes : []
      )

      narration = run_narrative_phase(result[:intent],
        pipeline: action_pipeline,
        mutations: result[:mutations])

      narrative_entry = {
        narrative: narration[:narrative],
        adventure_complete: narration[:adventure_complete],
        sequence_index: sequence_index,
        total_actions: total_actions,
        action_text: @loop&.player_intent&.truncate(200)
      }

      @on_narrative&.call(narrative_entry)
      narrative_entry
    end

    def action_queue_mode
      @adventure.effective_dm_setting("action_queue")
    end

    # True for both progressive modes — controls whether per-action narration runs at all.
    def per_action_narration?
      %w[progressive progressive_continuity].include?(action_queue_mode)
    end

    # True only for progressive_continuity — gates prior_action_outcomes usage.
    def action_queue_continuity?
      action_queue_mode == "progressive_continuity"
    end

    # Returns pipeline_outcome strings for all actions earlier in this turn,
    # ordered by sequence_index. Safe to call before @loop exists (returns []).
    def prior_action_outcomes
      return [] unless @loop && @log&.pipeline_run_id
      AdventureLoop.for_pipeline(@log.pipeline_run_id)
        .where("sequence_index < ?", @loop.sequence_index)
        .order(:sequence_index)
        .filter_map { |l| l.get("pipeline_outcome") }
    end

    def merge_result_intents(results)
      intents = results.map { |r| r[:intent] }.compact
      return intents.first if intents.size <= 1

      {
        intention: intents.map { |i| i[:intention] }.compact.join("; "),
        affected_contexts: intents.flat_map { |i| Array(i[:affected_contexts]) }.uniq,
        macro_significant: intents.any? { |i| i[:macro_significant] },
        domain_results: intents.last[:domain_results]
      }
    end

    def deep_merge_mutations(base, overlay)
      return overlay if base.blank?
      return base if overlay.blank?
      base.deep_merge(overlay)
    end

    # ----------------------------------------------------------------
    # Inter-action micro context update (between queued actions)
    # ----------------------------------------------------------------

    def run_inter_action_context_update(result)
      outcome = @loop&.get("pipeline_outcome")
      return unless outcome.present?

      run_context_updates(outcome, result[:mutations])
      @adventure.reload
      @loop&.batch_update!(
        timeline_entry: tl("inter_action_ctx", "Micro contexts updated between actions"))
    end

    # Run ContextUpdate before a roll-request pause. what_happened is constructed
    # from the player's intent and the rolls being requested — the mechanic has not
    # resolved yet, but the attempt is underway and contexts should reflect it.
    def run_context_updates_at_pause(intent, merged)
      rolls_desc = Array(merged[:player_rolls])
                     .map { |r| "#{r[:skill] || r[:type]} DC #{r[:dc]}" }.join(", ")
      what_happened = "Player attempting: #{intent[:intention]}. Pending rolls: #{rolls_desc}."
      run_context_updates(what_happened, nil)
    rescue => e
      @log.log!(:warn, "[pause_ctx_update] #{e.class}: #{e.message}")
    end

    # Run ContextUpdate before an initiative-pause from a Harbinger encounter.
    # The encounter scene is the outcome — contexts reflect combat beginning
    # before the player rolls initiative.
    def run_context_updates_at_encounter_pause(mutations)
      encounter_outcome = @loop&.get("pipeline_outcome")
      return unless encounter_outcome.present?
      run_context_updates(encounter_outcome, mutations)
    rescue => e
      @log.log!(:warn, "[encounter_pause_ctx_update] #{e.class}: #{e.message}")
    end

    # ----------------------------------------------------------------
    # ----------------------------------------------------------------
    # Helpers
    # ----------------------------------------------------------------

    def restore_from_metadata(metadata)
      intent = metadata["intent"]&.deep_symbolize_keys
      raise AiError, "Roll metadata missing intent — state integrity failure" unless intent
      mechanical_summaries = metadata["mechanical_summaries"] || []
      npc_actions  = (metadata["pending_npc_actions"]  || []).map(&:deep_symbolize_keys)
      consequences = (metadata["pending_consequences"] || []).map(&:deep_symbolize_keys)

      merged = {
        player_rolls: [], npc_actions: npc_actions,
        consequences: consequences, mechanical_summaries: mechanical_summaries
      }

      [intent, merged]
    end

    def story_has_plot_data?
      StoryNpc.where(story_id: @adventure.story_id).exists? ||
        StoryClue.where(story_id: @adventure.story_id).exists?
    end

    def resolve_plot(intent, verdict_outcome: nil, encounter_triggered: false)
      return unless story_has_plot_data?

      run_chronicler(intent, verdict_outcome: verdict_outcome, encounter_triggered: encounter_triggered)
    end

    # ----------------------------------------------------------------
    # Cross-domain roll deduplication
    # ----------------------------------------------------------------

    # Observability-only: detects duplicate rolls across domain evaluations and
    # logs a warning. Does NOT alter the rolls array — per Principle 17, code
    # must not heuristically fix AI-generated inconsistencies. If duplicates
    # appear, the MechEval prompt needs improvement.
    def warn_duplicate_rolls(merged)
      seen = {}
      duplicates = []
      merged[:player_rolls].each do |roll|
        key = [roll[:skill].to_s.downcase, roll[:type].to_s, roll[:dc].to_i]
        if seen[key]
          duplicates << "#{roll[:skill]} DC #{roll[:dc]} (#{roll[:domain]}) — duplicate of #{seen[key]}"
        else
          seen[key] = roll[:domain] || "unknown"
        end
      end
      @log.play_log!("duplicate_roll_warning", "#{duplicates.size} duplicate roll(s) from MechEval (not removed — fix prompt): #{duplicates.join('; ')}") if duplicates.any?
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

      @log.play_log!("auto_success_filter", "Warning: non-numeric DC on #{warned.join('; ')}") if warned.any?
      @log.play_log!("auto_success_filter", "Removed #{removed.size} roll(s): #{removed.join('; ')}") if removed.any?
      merged[:auto_successes] = removed if removed.any?
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
      @log.play_log!("queue_paused", "Action queue paused at action #{idx + 1}/#{total} (awaiting rolls). Remaining: #{remaining.inspect}")
    end

    def log_queue_interrupt(idx, total, remaining, reason: "encounter")
      return unless total > 1
      @log.play_log!("queue_interrupted", "Action queue interrupted at action #{idx + 1}/#{total} (#{reason}). Aborted: #{remaining.inspect}")
    end

    def log_queue_completed(total)
      @log.play_log!("queue_completed", "Action queue completed: #{total}/#{total} actions resolved")
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
        player_intent: action_text&.truncate(500),
        status: "pending"
      )
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
