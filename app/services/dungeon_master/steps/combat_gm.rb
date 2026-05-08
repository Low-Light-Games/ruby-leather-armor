# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Dedicated combat adjudicator after rolls when combat is active.
    # Replaces Mechanic in active combat for verdict + mutations; owns PF1e combat synthesis and battlefield patches.
    module CombatGm
      private

      def run_combat_gm(intent, merged, roll_results:, npc_results:, roll_requests:, submitted_rolls:)
        prompt_summary = "Combat GM: \"#{@log.truncate(intent[:intention])}\""

        raise Ai::Error, "Combat GM reached without a character sheet — cannot resolve combat" unless @sheet

        Battlefield::EnsureForActiveCombat.call(adventure: @adventure, sheet: @sheet)
        @adventure.reload

        char_block = CharacterBlock.full(@sheet)
        all_roll_results = [roll_results, npc_results].reject(&:blank?).join("\n\n")
        creature_stats = CharacterBlock.creature_stats_for(@adventure)
        battlefield_text = Battlefield::PromptSerializer.slice_for_adventure(@adventure)
        action_economy = (@adventure.combat_context || {})["action_economy"]
        combat_rules = Rules.guidance_for("combat")
        deterministic_facts = deterministic_combat_facts(roll_requests, submitted_rolls)
        scene_facts = retrieve_scene_facts_for_combat_gm(intent)

        system_prompt = Ai::PromptRenderer.render("combat_gm",
          character_block: char_block,
          mechanical_summaries_text: merged[:mechanical_summaries].join("\n\n"),
          roll_results: all_roll_results,
          deterministic_facts: deterministic_facts.presence,
          consequences: merged[:consequences].present? ? merged[:consequences].to_json : nil,
          scene_facts: scene_facts,
          creature_stats: creature_stats,
          battlefield_text: battlefield_text,
          action_economy_json: action_economy.present? ? action_economy.to_json : "(none)",
          combat_rules: combat_rules.presence || "(see core PF1e CRB combat chapter)",
          no_auto_hit_miss: @config.no_auto_hit_miss?,
          instant_death: @config.instant_death?)

        request_body = { system_prompt: system_prompt, user_message: intent[:intention] }

        parsed = timed_ai_call("combat_gm", prompt_summary, request_body) do
          raw = @ai.chat(system_prompt: system_prompt, user_message: intent[:intention],
                          step_name: "combat_gm", model: @config.model_for("combat_gm"))
          [raw, @ai.parse_json(raw)]
        end

        raise Ai::Error, "Combat GM returned no outcome — model produced: #{parsed.inspect.truncate(200)}" unless parsed["outcome"].present?

        parsed["outcome"] = deterministic_combat_outcome(roll_requests, submitted_rolls) || parsed["outcome"]

        {
          outcome:     parsed["outcome"],
          mutations:   parsed["mutations"] || {},
          npc_actions: Array(parsed["npc_actions"]).select { |a| a.is_a?(Hash) }
        }
      end

      def retrieve_scene_facts_for_combat_gm(intent)
        DungeonMaster::SceneFacts::ForResolution.call(
          adventure:   @adventure,
          intent_text: intent[:intention].to_s,
          ai:          @ai,
          log:         @log,
        )
      end

      def deterministic_combat_facts(roll_requests, submitted_rolls)
        attack_roll_facts(roll_requests, submitted_rolls).map do |fact|
          "#{fact[:label]} vs #{fact[:target]}: #{fact[:hit] ? 'HIT' : 'MISS'} (#{fact[:total]} vs #{fact[:defense_label]} #{fact[:dc]})"
        end.join("\n")
      end

      def deterministic_combat_outcome(roll_requests, submitted_rolls)
        facts = attack_roll_facts(roll_requests, submitted_rolls)
        return nil if facts.empty?

        facts.map do |fact|
          summary = "#{fact[:label]} vs #{fact[:target]}: #{fact[:hit] ? 'hit' : 'miss'} (#{fact[:total]} vs #{fact[:defense_label]} #{fact[:dc]})"
          if fact[:hit] && fact[:damage_total]
            damage = "#{fact[:damage_total]}"
            damage = "#{damage} #{fact[:damage_type]}" if fact[:damage_type].present?
            "#{summary} for #{damage} damage."
          else
            "#{summary}."
          end
        end.join(" ")
      end

      def attack_roll_facts(roll_requests, submitted_rolls)
        requests = Array(roll_requests).filter_map do |roll|
          next unless roll.is_a?(Hash)

          roll.deep_symbolize_keys
        end
        attack_rolls = requests.select { |roll| roll[:type].to_s == "attack_roll" }
        return [] if attack_rolls.empty?

        submitted_by_id, submitted_by_label = submitted_roll_indexes(submitted_rolls)
        attack_rolls.filter_map do |roll|
          total = submitted_roll_total_for(roll, submitted_by_id, submitted_by_label)
          next if total.nil?

          damage_roll = matching_damage_roll_for(requests, roll)
          damage_total = damage_roll ? submitted_roll_total_for(damage_roll, submitted_by_id, submitted_by_label) : nil
          {
            label: roll[:description].presence || "Attack",
            target: roll[:target].presence || "target",
            total: total,
            dc: roll[:dc].to_i,
            hit: total >= roll[:dc].to_i,
            defense_label: defense_label_for(roll[:defense_kind]),
            damage_total: damage_total,
            damage_type: damage_roll&.[](:damage_type).presence || roll[:damage_type].presence
          }
        end
      end

      def matching_damage_roll_for(roll_requests, attack_roll)
        source_id = attack_roll[:request_id].presence

        Array(roll_requests).find do |roll|
          next unless roll.is_a?(Hash)

          sym = roll.deep_symbolize_keys
          next unless sym[:type].to_s == "damage_roll"

          next true if source_id.present? && sym[:source_request_id].to_s == source_id.to_s

          sym[:target].to_s.casecmp?(attack_roll[:target].to_s) &&
            sym[:description].to_s.downcase.include?(attack_roll[:description].to_s.downcase)
        end
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

      def normalize_roll_label(label)
        label.to_s.downcase.gsub(/[^a-z0-9\s]/, " ").gsub(/\s+/, " ").strip
      end

      def defense_label_for(defense_kind)
        case defense_kind.to_s
        when "touch_ac"
          "Touch AC"
        when "flat_footed_ac"
          "Flat-Footed AC"
        else
          "AC"
        end
      end
    end
  end
end
