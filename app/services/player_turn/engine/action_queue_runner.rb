# frozen_string_literal: true

require "set"

module PlayerTurn
  class Engine
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
            prior_result = action_idx.positive? ? resolved_history[action_idx - 1] : nil
            accumulated << blocked_action_result(entry, prior_result)
            p.log.play_log!(
              "queue_action_blocked",
              "Blocked queued action #{action_idx + 1}/#{total} — #{entry.text.inspect} (failed prerequisite #{entry.prerequisite.inspect})"
            )
            break
          end

          action_text = entry.text
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
            remaining = remaining_action_entries(action_entries, idx)
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
            remaining = remaining_action_entries(action_entries, idx)
            qlog.log_pause(action_idx, total, remaining, reason: "awaiting initiative")
            qlog.clear_action_label
            return {
              action: :awaiting_initiative,
              intent: result[:intent],
              merged: result[:merged],
              pending_opening_merged: result[:pending_opening_merged] || result[:merged],
              creature_data: result[:creature_data],
              mutations: result[:mutations],
              remaining_actions: remaining
            }

          when :encounter
            p.loop&.batch_update!(new_status: "encounter",
              timeline_entry: p.send(:tl, "encounter", "Encounter triggered"))
            accumulated << result
            qlog.log_interrupt(action_idx, total, remaining_action_entries(action_entries, idx), reason: "encounter")
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
        Array(entries).filter_map { |entry| ActionQueueEntry.from_unknown(entry) }
      end

      def prerequisite_failed?(entry, action_idx, resolved_history)
        prerequisite = entry.prerequisite
        return false if prerequisite.blank?

        source_result = dependency_source_result(entry, action_idx, resolved_history)
        return true unless source_result

        case prerequisite
        when "stealth_approach_succeeded"
          !stealth_approach_succeeded?(source_result)
        else
          true
        end
      end

      def dependency_source_result(entry, action_idx, resolved_history)
        source_index = dependency_source_index(entry, action_idx)
        resolved_history[source_index]
      end

      def dependency_source_index(entry, action_idx)
        return action_idx - 1 if entry.depends_on_index.nil?

        entry.depends_on_index.to_i
      end

      def stealth_approach_succeeded?(result)
        ctx = result[:queue_resolution_context] || {}
        rolls = Array(ctx[:player_rolls]).map { |r| r.is_a?(Hash) ? r.deep_symbolize_keys : r }.select do |roll|
          next false unless roll.is_a?(Hash)

          roll[:type].to_s == "skill_check" && roll[:skill].to_s.casecmp("Stealth").zero?
        end
        return true if rolls.empty?

        submitted_entries = extract_submitted_rolls(ctx[:submitted_rolls])
        return false if submitted_entries.empty?

        requested_groups = group_equivalent_stealth_rolls(rolls)
        used_indexes = Set.new
        requested_groups.all? do |group|
          entry = find_matching_roll_entry(group, submitted_entries, used_indexes)
          entry && entry[:total].to_i >= group[:dc].to_i
        end
      end

      def extract_submitted_rolls(submitted_rolls)
        Array(submitted_rolls).filter_map do |roll|
          next unless roll.respond_to?(:deep_symbolize_keys)

          normalized = roll.deep_symbolize_keys
          {
            label: normalize_roll_label(normalized[:roll_description]),
            total: normalized[:roll_value].to_i
          }
        end
      end

      def find_matching_roll_entry(group, submitted_entries, used_indexes)
        idx = submitted_entries.each_with_index.find do |entry, i|
          next if used_indexes.include?(i)

          group[:labels].include?(entry[:label])
        end&.last

        if idx.nil?
          idx = submitted_entries.each_with_index.find do |entry, i|
            next if used_indexes.include?(i)

            group[:labels].any? { |label| roll_labels_similar?(entry[:label], label) }
          end&.last
        end

        return nil if idx.nil?

        used_indexes << idx
        submitted_entries[idx]
      end

      def group_equivalent_stealth_rolls(rolls)
        groups = []

        rolls.each do |roll|
          label = normalize_roll_label(roll[:description].presence || roll[:skill].presence || roll[:type].to_s)
          matching_group = groups.find do |group|
            group[:labels].any? { |existing| roll_labels_similar?(existing, label) }
          end

          if matching_group
            matching_group[:labels] << label unless matching_group[:labels].include?(label)
            matching_group[:dc] = [matching_group[:dc].to_i, roll[:dc].to_i].max
          else
            groups << { labels: [label], dc: roll[:dc].to_i }
          end
        end

        groups
      end

      def roll_labels_similar?(a, b)
        return false if a.blank? || b.blank?

        a_words = significant_roll_words(a)
        b_words = significant_roll_words(b)
        union = (a_words | b_words).size
        return true if union.zero?

        (a_words & b_words).size.to_f / union >= 0.30
      end

      def significant_roll_words(label)
        normalize_roll_label(label).scan(/[a-z0-9]+/) - %w[a an the to of for in on at with by from and or is it that this]
      end

      def normalize_roll_label(label)
        label.to_s.downcase.gsub(/[^a-z0-9\s]/, " ").gsub(/\s+/, " ").strip
      end

      def blocked_action_result(entry, prior_result)
        entry = normalize_action_entry(entry)
        prerequisite = entry.prerequisite
        blocked_text = entry.text

        BlockedActionResolution.new(
          action_text: blocked_text,
          action_outcome: blocked_action_outcome(blocked_text, prerequisite)
        ).to_h
      end

      def normalize_action_entry(entry)
        return entry if entry.is_a?(ActionQueueEntry)

        ActionQueueEntry.from_unknown(entry) || ActionQueueEntry.new(
          text: "",
          depends_on_index: nil,
          prerequisite: nil,
          abort_on_failed_prerequisite: false
        )
      end

      def blocked_action_outcome(action_text, prerequisite)
        case prerequisite
        when "stealth_approach_succeeded"
          "#{action_text} did not happen automatically because you were not in the stealthy position that setup required."
        else
          "#{action_text} did not happen automatically because its setup condition was not met."
        end
      end

      def finish_orchestrated(pipeline, queue_log, accumulated, action_narratives, use_per_action, total, action_count,
        abort_on_rejected:)
        queue_log.log_completed(total) if abort_on_rejected && total > 1

        if abort_on_rejected && use_per_action && action_narratives.any?
          if accumulated.any?
            final_narrative_result = pipeline.send(:run_accumulated_narrative_phase, accumulated)
            return final_narrative_result unless final_narrative_result[:action] == :narrated

            action_narratives << Narration::ProgressiveEntry.from_narrative_phase(
              final_narrative_result,
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

      def remaining_action_entries(action_entries, action_idx)
        Array(action_entries[(action_idx + 1)..]).map(&:to_h)
      end
    end
  end
end
