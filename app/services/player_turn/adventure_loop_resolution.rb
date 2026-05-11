# frozen_string_literal: true

module PlayerTurn
  module AdventureLoopResolution
    private

    def resolve(intention)
      result = run_evaluation_phase(intention)
      resolve_with_mechanics(result)
    end

    def run_evaluation_phase(intention)
      if combat_active?
        @current_cast_roster = PlayerTurn::CastRoster.empty
        run_combat_roll_request(intention)
      else
        @current_cast_roster = run_cast_resolve(intention)
        run_roll_request(intention, cast_roster: @current_cast_roster)
      end
    end

    def resolve_with_mechanics(result)
      capability = if skip_world_sanity_for_privileged_player?
                     @loop&.log_step("sanity_checker", "World: skipped (player opt-out)")
                     run_capability_check(result)
                   else
                     world, cap = run_sanity_gate_fan_out(result)
                     return world_check_rejection(result.to_intent_hash, world) unless world[:consistent]

                     @loop&.log_step("sanity_checker", "World: consistent")
                     cap
                   end

      return capability_check_rejection(result.to_intent_hash, capability) unless capability[:allowed]

      merged = build_merged_from_result(result)
      intent_hash = result.to_intent_hash
      return FlowResults.awaiting_rolls(intent: intent_hash, merged: merged).to_h if merged[:player_rolls].any?

      finish_resolution(intent_hash, merged, Rolls::PlayerRolls.auto_success_roll_message(merged))
    end

    def build_merged_from_result(result)
      merged = {
        player_rolls: result.player_rolls,
        npc_actions: [],
        consequences: result.consequences,
        mechanical_summaries: [result.mechanical_summary.to_s].reject(&:empty?)
      }
      Rolls::PlayerRolls.deduplicate_rolls!(merged, log: @log)
      Rolls::PlayerRolls.filter_auto_success_rolls!(merged, log: @log, sheet: @sheet)
      Rolls::PlayerRolls.assign_request_ids!(merged[:player_rolls])
      merged
    end

    def skip_world_sanity_for_privileged_player?
      true # @adventure.skip_world_sanity_check? && (@adventure.user.paid? || @adventure.user.admin)
    end

    def finish_resolution(intent, merged, roll_results, requested_rolls: nil, submitted_rolls: nil)
      current_roll_requests = Array(requested_rolls.presence || merged[:player_rolls]).map { |r| r.is_a?(Hash) ? r.deep_symbolize_keys : r }
      if (damage_pause = maybe_pause_for_damage_roll(intent, merged, current_roll_requests, roll_results, submitted_rolls))
        return damage_pause
      end

      roll_results, submitted_rolls = merge_roll_chain_results(merged, roll_results, submitted_rolls)
      verdict_roll_requests = merge_roll_chain_requests(merged, current_roll_requests)

      verdict_result = if combat_active?
                         run_combat_gm(intent, merged,
                           roll_results: roll_results,
                           npc_results: nil,
                           roll_requests: verdict_roll_requests,
                           submitted_rolls: submitted_rolls)
                       else
                         run_mechanic(intent, merged, roll_results: roll_results, npc_results: nil)
                       end
      verdict_step = combat_active? ? "combat_gm" : "mechanic"
      @loop&.batch_update!(
        new_data: { "verdict_outcome" => verdict_result[:outcome].to_s.truncate(500) },
        timeline_entry: { "step" => verdict_step, "summary" => verdict_result[:outcome].to_s.truncate(120), "at" => Time.current.iso8601 })
      apply_mutations(verdict_result[:mutations])

      time_result = run_time_keeper(intent, verdict_result)

      if time_result[:encounter]
        return dispatch_encounter_warmaster(intent, time_result, mutations: verdict_result[:mutations])
      end

      store_pipeline_outcome!(verdict_result[:outcome])

      maybe_run_world_turn(
        status: :resolved, intent: intent,
        mutations: verdict_result[:mutations],
        npc_actions: verdict_result[:npc_actions] || [],
        time_result: time_result,
        action_outcome: verdict_result[:outcome].to_s.presence,
        queue_resolution_context: {
          player_rolls: current_roll_requests.map { |r| r.is_a?(Hash) ? r.deep_dup : r },
          submitted_rolls: Array(submitted_rolls).map { |r| r.is_a?(Hash) ? r.deep_dup : r },
          roll_results: roll_results
        }
      )
    end

    def maybe_pause_for_damage_roll(intent, merged, current_roll_requests, roll_results, submitted_rolls)
      return nil if merged[:roll_chain].is_a?(Hash)

      hits = attack_rolls_requiring_damage(current_roll_requests, submitted_rolls)
      return nil if hits.empty?

      FlowResults.awaiting_rolls(
        intent: intent,
        merged: merged.merge(
          player_rolls: hits.map { |hit| build_damage_roll_request(hit) },
          roll_chain: {
            phase: "damage",
            prior_roll_results: roll_results,
            prior_submitted_rolls: Array(submitted_rolls).map { |r| r.is_a?(Hash) ? r.deep_dup : r },
            prior_roll_requests: Array(current_roll_requests).map { |r| r.is_a?(Hash) ? r.deep_dup : r }
          }
        )
      ).to_h
    end

    def attack_rolls_requiring_damage(current_roll_requests, submitted_rolls)
      attack_rolls = current_roll_requests.filter_map do |roll|
        next unless roll.is_a?(Hash)

        next unless roll[:type].to_s == "attack_roll"

        next if roll[:damage].blank?

        roll.deep_symbolize_keys
      end
      return [] if attack_rolls.empty?

      submitted_by_id, submitted_by_label = submitted_roll_indexes(submitted_rolls)

      attack_rolls.filter do |roll|
        total = submitted_roll_total_for(roll, submitted_by_id, submitted_by_label)
        total && total >= roll[:dc].to_i
      end
    end

    def build_damage_roll_request(attack_roll)
      attack_roll = attack_roll.deep_symbolize_keys
      {
        request_id: derived_damage_request_id(attack_roll),
        source_request_id: attack_roll[:request_id],
        type: "damage_roll",
        description: damage_roll_description_for(attack_roll),
        source_type: attack_roll[:source_type],
        source_id: attack_roll[:source_id],
        damage: attack_roll[:damage],
        damage_type: attack_roll[:damage_type],
        target: attack_roll[:target]
      }.compact
    end

    def damage_roll_description_for(attack_roll)
      source = attack_roll[:description].presence || attack_roll[:spell].presence || "attack"
      "Damage roll for #{source}"
    end

    def merge_roll_chain_results(merged, roll_results, submitted_rolls)
      chain = merged[:roll_chain]
      return [roll_results, submitted_rolls] unless chain.is_a?(Hash)

      combined_results = [chain[:prior_roll_results], roll_results].reject(&:blank?).join("\n")
      combined_submitted_rolls = Array(chain[:prior_submitted_rolls]).map { |r| r.is_a?(Hash) ? r.deep_dup : r } +
                                 Array(submitted_rolls).map { |r| r.is_a?(Hash) ? r.deep_dup : r }

      [combined_results, combined_submitted_rolls]
    end

    def merge_roll_chain_requests(merged, current_roll_requests)
      chain = merged[:roll_chain]
      return Array(current_roll_requests).map { |r| r.is_a?(Hash) ? r.deep_symbolize_keys : r } unless chain.is_a?(Hash)

      Array(chain[:prior_roll_requests]).map { |r| r.is_a?(Hash) ? r.deep_symbolize_keys : r } +
        Array(current_roll_requests).map { |r| r.is_a?(Hash) ? r.deep_symbolize_keys : r }
    end

    def normalize_roll_label(label)
      label.to_s.downcase.gsub(/[^a-z0-9\s]/, " ").gsub(/\s+/, " ").strip
    end

    def submitted_roll_indexes(submitted_rolls)
      Array(submitted_rolls).each_with_object([{}, {}]) do |roll, (by_id, by_label)|
        next unless roll.is_a?(Hash)

        normalized = roll.deep_symbolize_keys
        by_id[normalized[:request_id].to_s] = normalized[:roll_value].to_i if normalized[:request_id].present?
        by_label[normalize_roll_label(normalized[:roll_description])] = normalized[:roll_value].to_i
      end
    end

    def submitted_roll_total_for(roll, submitted_by_id, submitted_by_label)
      request_id = roll[:request_id].to_s
      return submitted_by_id[request_id] if request_id.present? && submitted_by_id.key?(request_id)

      submitted_by_label[normalize_roll_label(roll[:description])]
    end

    def derived_damage_request_id(attack_roll)
      base = attack_roll[:request_id].presence
      unless base.present?
        base = SecureRandom.uuid
        @log.play_log!(
          "warn",
          "Synthesized damage roll request_id without source request_id",
          parsed_response: { attack_roll: attack_roll }
        )
      end
      "#{base}:damage"
    end

    def dispatch_encounter_warmaster(intent, time_result, mutations:)
      result = Encounters::WarmasterBridge.call(
        loop: @loop, adventure: @adventure, sheet: @sheet, log: @log, config: @config, ai: @ai,
        intent: intent, time_result: time_result, mutations: mutations)
      store_pipeline_outcome!(result.pipeline_outcome)
      result.payload
    end

    def store_pipeline_outcome!(text)
      if text.blank?
        @log&.play_log!("empty_pipeline_outcome", "Terminal wrote blank pipeline_outcome — narration context will be missing")
      end

      @loop&.batch_update!(new_data: { "pipeline_outcome" => text.to_s.truncate(2000) })
    end
  end
end
