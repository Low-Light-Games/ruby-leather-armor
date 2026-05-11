# frozen_string_literal: true

module PlayerTurn
  module Steps
    module RollRequest
      RULES_TOP_K = 4
      BEATS_TOP_K = 6

      private

      def run_roll_request(intention, cast_roster: nil)
        broadcast_progress('Reading the situation...')

        scene_retrieval = retrieve_scene_for_roll_request(intention)
        rules           = retrieve_rules_for_roll_request(intention)

        ctx = RollRequest::Context.new(
          intent: intention,
          scene_retrieval: scene_retrieval,
          relevant_rules: rules,
          current_location_name: @adventure.current_location&.name,
          cast_roster: cast_roster,
        )

        prompt_summary = "RollRequest: \"#{@log.truncate(intention)}\""
        system_prompt  = Ai::PromptRenderer.render('roll_request',
                                               roll_request_context: ctx)
        request_body   = { system_prompt: system_prompt, user_message: intention }

        parsed = timed_ai_call('roll_request', prompt_summary, request_body) do
          raw = @ai.chat(
            system_prompt: system_prompt,
            user_message: intention,
            step_name: 'roll_request',
            model: @config.model_for('roll_request'),
            reasoning_effort: @config.reasoning_effort_for('roll_request')
          )
          [raw, @ai.parse_json(raw)]
        end

        result = build_roll_request_evaluation_result(parsed: parsed, intention: intention)

        warn_on_invented_rule_slug!(parsed, rules)
        log_roll_request_to_loop(result)

        Rolls::PlayerRolls.compute_take_values!(result.player_rolls, sheet: @sheet)
        result
      end

      def build_roll_request_evaluation_result(parsed:, intention:)
        parsed = (parsed || {}).deep_symbolize_keys
        rolls = if needs_roll?(parsed)
                  [normalize_roll(parsed[:roll], mechanical_summary: parsed[:mechanical_summary])]
                else
                  []
                end

        EvaluationResult.new(
          intention: intention,
          destination: parsed[:destination],
          combat_transition: parsed[:transition],
          combat_combatants: normalized_combatants(parsed[:combatants]),
          player_rolls: rolls,
          consequences: PlayerTurn::Rolls::Consequences.normalize(parsed[:consequences]),
          mechanical_summary: parsed[:mechanical_summary].to_s.presence || '(no mechanical summary)'
        )
      end

      def needs_roll?(parsed)
        parsed[:needs_roll] == true && parsed[:roll].is_a?(Hash)
      end

      def normalize_roll(raw, mechanical_summary:)
        raw = raw.deep_symbolize_keys
        {
          type: raw[:type].presence || 'skill_check',
          skill: raw[:skill],
          save: raw[:save],
          dc: raw[:dc],
          description: raw[:description].presence || mechanical_summary.to_s.presence || '(no description)',
          rule_slug: raw[:rule_slug],
          take_10_eligible: raw[:take_10_eligible] == true,
          take_20_eligible: raw[:take_20_eligible] == true,
          situational_modifiers: PlayerTurn::Rolls::SituationalModifiers.normalize(raw[:situational_modifiers])
        }.compact
      end

      def normalized_combatants(raw)
        Array(raw).flat_map do |entry|
          case entry
          when Hash
            key, value = entry.to_a.first
            count = value.to_i
            count.positive? ? Array.new(count, key.to_s) : [key.to_s]
          else
            [entry.to_s]
          end
        end.reject(&:blank?)
      end

      def warn_on_invented_rule_slug!(parsed, retrieved_rules)
        return unless parsed.is_a?(Hash) && parsed['needs_roll'] == true

        roll = parsed['roll']
        return unless roll.is_a?(Hash)

        emitted_slug = roll['rule_slug'].to_s
        return if emitted_slug.empty?

        retrieved_slugs = retrieved_rules.map { |r| r[:slug].to_s }
        return if retrieved_slugs.include?(emitted_slug)

        @log.play_log!(
          'roll_request_invented_slug',
          "RollRequest: AI emitted rule_slug '#{emitted_slug}' not in retrieved set #{retrieved_slugs.inspect}",
          parsed_response: {
            emitted_skill: roll['skill'],
            emitted_dc: roll['dc'],
            emitted_slug: emitted_slug,
            retrieved_slugs: retrieved_slugs
          }
        )
      end

      # Orchestrator-tool path: the GameMaster phase dispatches
      # `request_roll` as a tool call. CastResolver runs as an
      # invisible pre-step here too — the orchestrator doesn't see
      # it (no Tools::Registry entry) but the new identity contract
      # holds the moment `use_game_master?` flips on, exactly as it
      # does on the Sequencer path.
      def run_roll_request_as_ai_called_tool(intention)
        cast_roster      = run_cast_resolve(intention)
        @current_cast_roster = cast_roster
        scene_retrieval  = retrieve_scene_for_roll_request(intention)
        rules            = retrieve_rules_for_roll_request(intention)

        ctx = RollRequest::Context.new(
          intent: intention,
          scene_retrieval: scene_retrieval,
          relevant_rules: rules,
          current_location_name: @adventure.current_location&.name,
          cast_roster: cast_roster,
        )

        prompt_summary = "RequestRoll (tool): \"#{@log.truncate(intention)}\""
        system_prompt  = Ai::PromptRenderer.render('roll_request_as_tool',
                                               roll_request_context: ctx)
        request_body   = { system_prompt: system_prompt, user_message: intention }

        parsed = timed_ai_call('request_roll_tool', prompt_summary, request_body) do
          raw = @ai.chat(
            system_prompt: system_prompt,
            user_message: intention,
            step_name: 'request_roll_tool',
            model: @config.model_for('request_roll_tool'),
            reasoning_effort: @config.reasoning_effort_for('request_roll_tool')
          )
          [raw, @ai.parse_json(raw)]
        end

        Tools::RequestRoll::Result.from_parsed(parsed, sheet: @sheet)
      end

      def retrieve_scene_for_roll_request(intention)
        SceneRetrieval::ForResolution.call(
          adventure:   @adventure,
          intent_text: intention,
          ai:          @ai,
          log:         @log,
          fact_limit:  BEATS_TOP_K,
        )
      end

      def retrieve_rules_for_roll_request(intention)
        Rules::Lookup.call(
          ai: @ai,
          log: @log,
          query_text: intention,
          limit: RULES_TOP_K
        )
      end

      def log_roll_request_to_loop(result)
        return unless @loop

        rolls_desc = result.player_rolls
                           .map { |r| "#{r[:skill] || r[:type]} DC #{r[:dc]}" }
                           .join(', ')

        @loop.batch_update!(
          new_data: { 'roll_request' => true },
          new_status: 'resolving',
          timeline_entry: {
            'step' => 'roll_request',
            'summary' => rolls_desc.presence || 'No rolls',
            'at' => Time.current.iso8601
          }
        )
      end
    end
  end
end
