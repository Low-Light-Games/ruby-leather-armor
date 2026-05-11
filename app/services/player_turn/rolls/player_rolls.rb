# frozen_string_literal: true

module PlayerTurn
  module Rolls
    class PlayerRolls
      class << self
        def tag_roll_resolution!(adventure_loop, roll_results)
          return unless adventure_loop

          text = roll_results.to_s.downcase
          if text.include?("take 20")
            adventure_loop.batch_update!(
              new_tags: { "took_20" => true },
              new_data: { "resolution_method" => "take_20", "roll_results" => roll_results.to_s.truncate(500) })
          elsif text.include?("take 10")
            adventure_loop.batch_update!(
              new_tags: { "took_10" => true },
              new_data: { "resolution_method" => "take_10", "roll_results" => roll_results.to_s.truncate(500) })
          else
            adventure_loop.batch_update!(
              new_tags: { "rolled" => true },
              new_data: { "resolution_method" => "roll", "roll_results" => roll_results.to_s.truncate(500) })
          end
        end

        def deduplicate_rolls!(merged, log:)
          seen = {}
          removed = []
          kept_conflicts = []

          merged[:player_rolls].reject! do |roll|
            key = [roll[:skill].to_s.downcase, roll[:type].to_s, roll[:dc].to_i]
            first = seen[key]

            if first
              if roll_descriptions_similar?(first[:description], roll[:description])
                removed << "#{roll[:skill]} DC #{roll[:dc]} — duplicate"
                true
              else
                kept_conflicts << "#{roll[:skill]} DC #{roll[:dc]}: \"#{first[:description]}\" vs \"#{roll[:description]}\""
                false
              end
            else
              seen[key] = roll
              false
            end
          end

          log.play_log!("duplicate_rolls_removed",
            "Removed #{removed.size} duplicate roll(s): #{removed.join('; ')}") if removed.any?
          log.play_log!("duplicate_rolls_kept_conflict",
            "#{kept_conflicts.size} same-key roll(s) kept (descriptions differ — review MechEval): #{kept_conflicts.join('; ')}") if kept_conflicts.any?
        end

        def filter_auto_success_rolls!(merged, log:, sheet:)
          skills_lookup = skills_lookup_from_sheet(sheet)
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

          log.play_log!("auto_success_filter", "Warning: non-numeric DC on #{warned.join('; ')}") if warned.any?
          log.play_log!("auto_success_filter", "Removed #{removed.size} roll(s): #{removed.join('; ')}") if removed.any?
          merged[:auto_successes] = removed if removed.any?
        end

        def auto_success_roll_message(merged)
          descs = (merged[:auto_successes] || []).map { |s| "AUTO-SUCCESS: #{s}" }
          descs.any? ? descs.join("\n") : nil
        end

        def skills_lookup_from_sheet(sheet)
          return {} unless sheet&.derived_stats.is_a?(Hash)

          Array(sheet.derived_stats["skills"]).each_with_object({}) do |skill, h|
            h[skill["name"].to_s] = skill["total"].to_i if skill["name"].present?
          end
        end

        def compute_take_values!(rolls, sheet:)
          skills_lookup = skills_lookup_from_sheet(sheet)
          Array(rolls).each do |roll|
            next unless roll.is_a?(Hash)

            next unless roll[:type].to_s == "skill_check" && roll[:skill].present?

            mod = skills_lookup[roll[:skill].to_s].to_i
            roll[:take_10_value] = 10 + mod
            roll[:take_20_value] = 20 + mod
          end
          rolls
        end

        def assign_request_ids!(rolls)
          Array(rolls).each do |roll|
            next unless roll.is_a?(Hash)

            roll[:request_id] ||= SecureRandom.uuid
          end
        end

        private

        def roll_descriptions_similar?(a, b)
          stop = %w[a an the to of for in on at with by from and or is it that this i]
          words = ->(s) { s.to_s.downcase.scan(/[a-z]+/) - stop }
          wa = words.call(a).to_set
          wb = words.call(b).to_set
          union = (wa | wb).size
          return true if union.zero?

          (wa & wb).size.to_f / union >= 0.30
        end

        def auto_success_reason(roll, dc, skills_lookup)
          return "DC <= 0 (impossible to fail)" if dc <= 0

          if roll[:type].to_s == "skill_check"
            modifier = skills_lookup[roll[:skill].to_s]
            if modifier && (modifier + 1) >= dc
              return "modifier #{modifier} guarantees success (min roll 1 + #{modifier} = #{modifier + 1} >= DC #{dc})"
            end
          end

          nil
        end

        def numeric_dc?(value)
          value.is_a?(Integer) || (value.is_a?(String) && value.match?(/\A\d+\z/))
        end
      end
    end
  end
end
