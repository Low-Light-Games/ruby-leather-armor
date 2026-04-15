# frozen_string_literal: true

module DungeonMaster
  class PipelineEngine
    # Centralizes the per-action resolve loop + `case result[:status]` that
    # previously duplicated `orchestrate_actions` and `run_remaining_queue`.
    #
    # Assumes:
    #   - `pipeline` has @adventure, @log, @config, @ai, @sheet and mixin-provided
    #     private helpers: create_adventure_loop, resolve, tl, plus PipelineEngine::Concerns
    #     NarrationCoordination (per-action + accumulated narrate), ContextCoordination
    #     (inter-action + encounter-pause context updates).
    #   - Action-queue log lines use PipelineEngine::ActionQueueLog (see action_queue_log.rb).
    #   - Before each `resolve`, @loop is bound to the AdventureLoop for that
    #     action index (this runner assigns it).
    #
    # Sets:
    #   - pipeline.@loop per iteration; clears log action_label when finished.
    #   - AdventureLoop rows and timeline entries via batch_update! as today.
    #
    # Prompts:
    #   - None directly; `resolve` delegates to AdventureLoopResolution / step mixins.
    #
    # Semantics:
    #   - `abort_on_rejected: true` — first :rejected returns immediately (fresh queue).
    #   - `abort_on_rejected: false` — :rejected marks loop errored and continues (resume queue).
    class ActionQueueRunner
      def initialize(pipeline_engine)
        @pipeline_engine = pipeline_engine
      end

      # @param per_action_narration [Boolean] orchestrate path only; ignored for resume.
      def run(action_strings:, base_sequence_index:, total_for_logging:, abort_on_rejected:,
        initial_accumulated: [], per_action_narration: false)
        p = @pipeline_engine
        qlog = ActionQueueLog.new(p.log)
        action_entries = normalize_action_entries(action_strings)
        accumulated = initial_accumulated.dup
        resolved_history = initial_accumulated.dup
        action_narratives = []
        use_per_action = per_action_narration && action_strings.size > 1
        total = total_for_logging

        action_entries.each_with_index do |entry, idx|
          action_idx = base_sequence_index + idx
          if prerequisite_failed?(entry, action_idx, resolved_history)
            p.log.play_log!(
              "queue_action_blocked",
              "Blocked queued action #{action_idx + 1}/#{total} — #{entry_text(entry).inspect} (failed prerequisite #{entry_prerequisite(entry).inspect})"
            )
            break
          end

          action_text = entry_text(entry)
          qlog.set_action_label(action_idx, total)
          bind_loop!(p.send(:create_adventure_loop, action_text, action_idx))
          result = p.send(:resolve, action_text)

          case result[:status]
          when :rejected
            p.loop&.batch_update!(new_status: "errored",
              timeline_entry: p.send(:tl, "rejected", result[:reason]))
            if abort_on_rejected
              qlog.clear_action_label
              return { action: :rejected, reason: result[:reason], dm_message: result[:dm_message] }
            end
            next

          when :awaiting_rolls
            p.loop&.batch_update!(new_status: "paused",
              timeline_entry: p.send(:tl, "awaiting_rolls", "Paused for player rolls"))
            ContextUpdatePause.run(pipeline_engine: p, intent: result[:intent], merged: result[:merged])
            remaining = action_entries[(idx + 1)..]
            qlog.log_pause(action_idx, total, remaining, reason: "awaiting rolls")
            qlog.clear_action_label
            return {
              action: :awaiting_rolls, intent: result[:intent], merged: result[:merged],
              remaining_actions: remaining
            }

          when :awaiting_initiative
            p.loop&.batch_update!(new_status: "paused",
              new_tags: { "combat_started" => true },
              timeline_entry: p.send(:tl, "awaiting_initiative", "Paused for player initiative"))
            p.send(:run_context_updates_at_encounter_pause, result[:mutations])
            remaining = action_entries[(idx + 1)..]
            qlog.log_pause(action_idx, total, remaining, reason: "awaiting initiative")
            qlog.clear_action_label
            return {
              action: :awaiting_initiative,
              intent: result[:intent],
              merged: result[:merged],
              creature_data: result[:creature_data],
              mutations: result[:mutations],
              remaining_actions: remaining
            }

          when :encounter, :social_scene
            label = result[:status].to_s
            summary = (result[:status] == :encounter) ? "Encounter triggered" : "Social scene triggered"
            p.loop&.batch_update!(new_status: label,
              timeline_entry: p.send(:tl, label, summary))
            accumulated << result
            qlog.log_interrupt(action_idx, total, action_entries[(idx + 1)..], reason: label)
            break

          when :resolved
            p.loop&.batch_update!(new_status: "resolved",
              timeline_entry: p.send(:tl, "resolved", "Action resolved"))
            resolved_history << result
            if abort_on_rejected && use_per_action
              action_narratives << p.send(:run_single_action_narrative_phase, result, idx, action_strings.size)
              p.send(:run_inter_action_context_update, result) if idx < action_strings.size - 1
            else
              accumulated << result
              p.send(:run_inter_action_context_update, result) if idx < action_strings.size - 1
            end
          end
        end

        qlog.clear_action_label
        finish_orchestrated(p, qlog, accumulated, action_narratives, use_per_action, total, action_strings.size,
          abort_on_rejected: abort_on_rejected)
      end

      private

      def bind_loop!(adventure_loop)
        @pipeline_engine.bind_current_loop!(adventure_loop)
      end

      def normalize_action_entries(entries)
        Array(entries).filter_map do |entry|
          case entry
          when String
            {
              "text" => entry,
              "depends_on_index" => nil,
              "prerequisite" => nil,
              "abort_on_failed_prerequisite" => false
            }
          when Hash
            text = (entry["text"] || entry[:text]).to_s
            next if text.blank?

            {
              "text" => text,
              "depends_on_index" => entry["depends_on_index"] || entry[:depends_on_index],
              "prerequisite" => entry["prerequisite"] || entry[:prerequisite],
              "abort_on_failed_prerequisite" => (entry["abort_on_failed_prerequisite"] || entry[:abort_on_failed_prerequisite]) == true
            }
          end
        end
      end

      def entry_text(entry)
        (entry["text"] || entry[:text]).to_s
      end

      def entry_prerequisite(entry)
        raw = entry["prerequisite"] || entry[:prerequisite]
        raw.present? ? raw.to_s : nil
      end

      def prerequisite_failed?(entry, action_idx, resolved_history)
        prerequisite = entry_prerequisite(entry)
        return false if prerequisite.blank?

        depends_on_index = entry["depends_on_index"] || entry[:depends_on_index]
        source_index = depends_on_index.nil? ? (action_idx - 1) : depends_on_index.to_i
        source_result = resolved_history[source_index]
        return true unless source_result

        case prerequisite
        when "stealth_approach_succeeded"
          !stealth_approach_succeeded?(source_result)
        else
          true
        end
      end

      def stealth_approach_succeeded?(result)
        ctx = result[:queue_resolution_context] || {}
        rolls = Array(ctx[:player_rolls]).map { |r| r.is_a?(Hash) ? r.deep_symbolize_keys : r }.select do |roll|
          next false unless roll.is_a?(Hash)

          roll[:type].to_s == "skill_check" && roll[:skill].to_s.casecmp("Stealth").zero?
        end
        return false if rolls.empty?

        submitted_totals = extract_roll_totals(ctx[:roll_results])
        return false if submitted_totals.size < rolls.size

        rolls.each_with_index.all? do |roll, idx|
          submitted_totals[idx] >= roll[:dc].to_i
        end
      end

      def extract_roll_totals(roll_results)
        text = roll_results.to_s
        return [] if text.blank?

        text.scan(/(?:rolled|total)\s+(-?\d+)/i).flatten.map(&:to_i)
      end

      def finish_orchestrated(pipeline, queue_log, accumulated, action_narratives, use_per_action, total, action_count,
        abort_on_rejected:)
        queue_log.log_completed(total) if abort_on_rejected && total > 1

        if abort_on_rejected && use_per_action && action_narratives.any?
          if accumulated.any?
            final = pipeline.send(:run_accumulated_narrative_phase, accumulated)
            return final unless final[:action] == :narrated
            action_narratives << Narrative::ProgressiveEntry.from_narrative_phase(
              final,
              sequence_index: action_narratives.size,
              total_actions: action_count,
              action_text: nil
            ).to_h
          end
          { action: :narrated_sequence, narratives: action_narratives }
        else
          pipeline.send(:run_accumulated_narrative_phase, accumulated)
        end
      end
    end
  end
end
