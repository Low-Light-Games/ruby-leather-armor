# frozen_string_literal: true

module DungeonMaster
  class Pipeline
    # Centralizes the per-action resolve loop + `case result[:status]` that
    # previously duplicated `orchestrate_actions` and `run_remaining_queue`.
    #
    # Assumes:
    #   - `pipeline` has @adventure, @log, @config, @ai, @sheet and mixin-provided
    #     private helpers: create_adventure_loop, resolve, set_action_label,
    #     clear_action_label, run_single_action_narrative_phase,
    #     run_inter_action_context_update, run_context_updates_at_pause,
    #     run_context_updates_at_encounter_pause, log_queue_pause,
    #     log_queue_interrupt, log_queue_completed, run_accumulated_narrative_phase, tl.
    #   - Before each `resolve`, @loop is bound to the AdventureLoop for that
    #     action index (this runner assigns it).
    #
    # Sets:
    #   - pipeline.@loop per iteration; clears log action_label when finished.
    #   - AdventureLoop rows and timeline entries via batch_update! as today.
    #
    # Prompts:
    #   - None directly; `resolve` delegates to CoreResolver / step mixins.
    #
    # Semantics:
    #   - `abort_on_rejected: true` — first :rejected returns immediately (fresh queue).
    #   - `abort_on_rejected: false` — :rejected marks loop errored and continues (resume queue).
    class ActionQueueRunner
      def initialize(pipeline)
        @pipeline = pipeline
      end

      # @param per_action_narration [Boolean] orchestrate path only; ignored for resume.
      def run(action_strings:, base_sequence_index:, total_for_logging:, abort_on_rejected:,
        initial_accumulated: [], per_action_narration: false)
        p = @pipeline
        accumulated = initial_accumulated.dup
        action_narratives = []
        use_per_action = per_action_narration && action_strings.size > 1
        total = total_for_logging

        action_strings.each_with_index do |action_text, idx|
          action_idx = base_sequence_index + idx
          p.send(:set_action_label, action_idx, total)
          bind_loop!(p.send(:create_adventure_loop, action_text, action_idx))
          result = p.send(:resolve, action_text)

          case result[:status]
          when :rejected
            p.loop&.batch_update!(new_status: "errored",
              timeline_entry: p.send(:tl, "rejected", result[:reason]))
            if abort_on_rejected
              p.send(:clear_action_label)
              return { action: :rejected, reason: result[:reason], dm_message: result[:dm_message] }
            end
            next

          when :awaiting_rolls
            p.loop&.batch_update!(new_status: "paused",
              timeline_entry: p.send(:tl, "awaiting_rolls", "Paused for player rolls"))
            p.send(:run_context_updates_at_pause, result[:intent], result[:merged])
            remaining = action_strings[(idx + 1)..]
            p.send(:log_queue_pause, action_idx, total, remaining)
            p.send(:clear_action_label)
            return {
              action: :awaiting_rolls, intent: result[:intent], merged: result[:merged],
              remaining_actions: remaining
            }

          when :awaiting_initiative
            p.loop&.batch_update!(new_status: "paused",
              new_tags: { "combat_started" => true },
              timeline_entry: p.send(:tl, "awaiting_initiative", "Paused for player initiative"))
            p.send(:run_context_updates_at_encounter_pause, result[:mutations])
            remaining = action_strings[(idx + 1)..]
            p.send(:log_queue_pause, action_idx, total, remaining)
            p.send(:clear_action_label)
            return {
              action: :awaiting_initiative,
              intent: result[:intent],
              creature_data: result[:creature_data],
              mutations: result[:mutations],
              remaining_actions: remaining
            }

          when :encounter
            p.loop&.batch_update!(new_status: "encounter",
              timeline_entry: p.send(:tl, "encounter", "Encounter triggered"))
            accumulated << result
            p.send(:log_queue_interrupt, action_idx, total, action_strings[(idx + 1)..], reason: "encounter")
            break

          when :social_scene
            p.loop&.batch_update!(new_status: "social_scene",
              timeline_entry: p.send(:tl, "social_scene", "Social scene triggered"))
            accumulated << result
            p.send(:log_queue_interrupt, action_idx, total, action_strings[(idx + 1)..], reason: "social_scene")
            break

          when :resolved
            p.loop&.batch_update!(new_status: "resolved",
              timeline_entry: p.send(:tl, "resolved", "Action resolved"))
            if abort_on_rejected && use_per_action
              action_narratives << p.send(:run_single_action_narrative_phase, result, idx, action_strings.size)
              p.send(:run_inter_action_context_update, result) if idx < action_strings.size - 1
            else
              accumulated << result
              p.send(:run_inter_action_context_update, result) if idx < action_strings.size - 1
            end
          end
        end

        p.send(:clear_action_label)
        finish_orchestrated(p, accumulated, action_narratives, use_per_action, total, action_strings.size,
          abort_on_rejected: abort_on_rejected)
      end

      private

      def bind_loop!(adventure_loop)
        @pipeline.instance_variable_set(:@loop, adventure_loop)
      end

      def finish_orchestrated(pipeline, accumulated, action_narratives, use_per_action, total, action_count,
        abort_on_rejected:)
        pipeline.send(:log_queue_completed, total) if abort_on_rejected && total > 1

        if abort_on_rejected && use_per_action && action_narratives.any?
          if accumulated.any?
            final = pipeline.send(:run_accumulated_narrative_phase, accumulated)
            return final unless final[:action] == :narrated
            action_narratives << {
              narrative: final[:narrative],
              adventure_complete: final[:adventure_complete],
              sequence_index: action_narratives.size,
              total_actions: action_count,
              action_text: nil
            }
          end
          { action: :narrated_sequence, narratives: action_narratives }
        else
          pipeline.send(:run_accumulated_narrative_phase, accumulated)
        end
      end
    end
  end
end
