# frozen_string_literal: true

module PlayerTurn
  module Steps
    module RollRequest
      RULES_TOP_K = 4
      BEATS_TOP_K = 6
      DEFAULT_MIN_CONFIDENCE = 60

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

        parsed = sanitize_low_confidence_roll_request(parsed)
        result = build_roll_request_evaluation_result(parsed: parsed, intention: intention,
                                                      cast_roster: cast_roster)
        log_roll_request_to_loop(result)

        return result if attack_roll_only?(result)

        apply_opposed_dc_resolution!(result)
        Rolls::PlayerRolls.compute_take_values!(result.player_rolls, sheet: @sheet)
        result
      end

      def apply_opposed_dc_resolution!(result)
        return unless result.target_actor_sheet_id

        target_sheet = @adventure.adventure_actor_sheets.find_by(id: result.target_actor_sheet_id)
        return unless target_sheet

        result.player_rolls.each do |roll|
          next unless roll.is_a?(Hash)

          next unless roll[:type].to_s == "skill_check"

          roll[:dc] = Mechanics::OpposedRollResolution.resolve_dc(
            roll: roll, target_sheet: target_sheet, log: @log,
          )
        end
      end

      def build_roll_request_evaluation_result(parsed:, intention:, cast_roster: nil)
        parsed = (parsed || {}).deep_symbolize_keys
        rolls = if needs_roll?(parsed)
                  [normalize_roll(parsed[:roll], mechanical_summary: parsed[:mechanical_summary])]
                else
                  []
                end

        EvaluationResult.new(
          intention: intention,
          combat_transition: parsed[:transition],
          target_actor_sheet_id: validated_target_id(parsed[:target_actor_sheet_id], cast_roster: cast_roster),
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
        type = raw[:type].presence || 'skill_check'
        skill = raw[:skill]
        save = raw[:save]
        {
          type: type,
          skill: skill,
          save: save,
          dc: raw[:dc],
          failure_result: raw[:failure_result].to_s.presence,
          description: raw[:description].presence || mechanical_summary.to_s.presence || '(no description)',
          rule_slug: rule_slug_from_roll(type: type, skill: skill, save: save),
          take_10_eligible: raw[:take_10_eligible] == true,
          take_20_eligible: raw[:take_20_eligible] == true,
          situational_modifiers: PlayerTurn::Rolls::SituationalModifiers.normalize(raw[:situational_modifiers])
        }.compact
      end

      # @return [Integer, nil]
      def validated_target_id(raw, cast_roster:)
        return nil if raw.nil? || raw == ""

        id = Integer(raw, exception: false)
        return nil unless id&.positive?

        roster = cast_roster || PlayerTurn::CastRoster.empty
        return id if roster.find_by_actor_sheet_id(id)

        @log.play_log!(
          'roll_request_unknown_target',
          "RollRequest emitted target_actor_sheet_id=#{id} not in cast roster",
          parsed_response: UnknownTargetEvent.new(
            emitted_target_id: id,
            roster_ids:        roster.members.map(&:actor_sheet_id),
            roster_names:      roster.members.map(&:name),
          ).to_h
        )
        nil
      end

      def attack_roll_only?(result)
        rolls = Array(result.player_rolls)
        rolls.length == 1 && rolls.first.is_a?(Hash) && rolls.first[:type].to_s == 'attack_roll'
      end

      def sanitize_low_confidence_roll_request(parsed)
        payload = (parsed || {}).deep_symbolize_keys
        return payload unless low_confidence_roll_request?(payload)

        confidence = roll_request_confidence(payload)
        @log.play_log!(
          'roll_request_low_confidence',
          "RollRequest confidence #{confidence} below threshold #{minimum_roll_request_confidence}; forcing no-roll.",
          parsed_response: {
            confidence: confidence,
            threshold: minimum_roll_request_confidence,
            roll_type: payload.dig(:roll, :type),
            skill: payload.dig(:roll, :skill),
            reasoning: payload[:reasoning]
          }
        )
        payload.merge(
          needs_roll: false,
          no_roll_reason: "Low confidence roll request (#{confidence}/100 < #{minimum_roll_request_confidence}/100)",
          roll: nil
        )
      end

      def low_confidence_roll_request?(payload)
        return false unless needs_roll?(payload)

        return false if payload.dig(:roll, :type).to_s == 'attack_roll'

        roll_request_confidence(payload) < minimum_roll_request_confidence
      end

      def roll_request_confidence(payload)
        value = payload[:confidence]
        parsed = Integer(value, exception: false)
        return 100 if parsed.nil?

        parsed.clamp(0, 100)
      end

      def minimum_roll_request_confidence
        raw = @config.get('roll_request_min_confidence')
        parsed = Integer(raw, exception: false)
        return DEFAULT_MIN_CONFIDENCE if parsed.nil?

        parsed.clamp(0, 100)
      end

      def rule_slug_from_roll(type:, skill:, save:)
        return 'attack_roll' if type.to_s == 'attack_roll'

        source = skill.presence || save.presence
        return nil if source.blank?

        source.to_s
          .downcase
          .gsub(/\([^)]*\)/, '')
          .gsub(/[^a-z0-9]+/, '_')
          .gsub(/\A_+|_+\z/, '')
      end

      def run_roll_request_as_ai_called_tool(intention)
        @current_cast_roster = run_cast_resolve(intention)
        scene_retrieval  = retrieve_scene_for_roll_request(intention)
        rules            = retrieve_rules_for_roll_request(intention)

        ctx = RollRequest::Context.new(
          intent: intention,
          scene_retrieval: scene_retrieval,
          relevant_rules: rules,
          current_location_name: @adventure.current_location&.name,
          cast_roster: @current_cast_roster,
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
