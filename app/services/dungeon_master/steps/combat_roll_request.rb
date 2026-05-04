# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step: CombatRollRequest — single AI call that adjudicates
    # combat-active free-text turns. Mirrors {Steps::RollRequest} but
    # carries combat-aware context (attack options, action economy,
    # threats, battlefield) so the model can pick a roll that fits the
    # tactical state.
    #
    # The AI receives attack options / threats / battlefield text but no
    # character sheet — combat DCs and bonuses resolve post-call from the
    # sheet via {Phases::CombatMechanicResolution}, which clamps the
    # AI-emitted `attack_option_id` against the live attack options.
    #
    # Returns an {EvaluationResult} built directly from the parsed JSON.
    module CombatRollRequest
      RULES_TOP_K = 4
      BEATS_TOP_K = 6
      DEFAULT_PROMPT_PROGRESS = 'Adjudicating your move...'

      private

      def run_combat_roll_request(intention)
        broadcast_progress(DEFAULT_PROMPT_PROGRESS)

        ctx = CombatRollRequest::Context.build(
          intent: intention, adventure: @adventure, sheet: @sheet,
          ai: @ai, log: @log,
          rules_top_k: RULES_TOP_K, beats_top_k: BEATS_TOP_K
        )
        prompt_summary = "CombatRollRequest: \"#{@log.truncate(intention)}\""
        system_prompt = PromptRenderer.render('combat_roll_request', combat_roll_request_context: ctx)
        request_body = { system_prompt: system_prompt, user_message: intention }

        parsed = timed_ai_call('combat_roll_request', prompt_summary, request_body) do
          raw = @ai.chat(
            system_prompt: system_prompt,
            user_message: intention,
            step_name: 'combat_roll_request',
            model: @config.model_for('combat_roll_request'),
            reasoning_effort: @config.reasoning_effort_for('combat_roll_request')
          )
          [raw, @ai.parse_json(raw)]
        end

        result = build_combat_roll_request_evaluation_result(parsed: parsed, intention: intention)

        log_combat_roll_request_to_loop(result)
        Rolls::PlayerRolls.compute_take_values!(result.player_rolls, sheet: @sheet)
        result
      end

      def build_combat_roll_request_evaluation_result(parsed:, intention:)
        parsed = (parsed || {}).deep_symbolize_keys
        rolls = needs_roll?(parsed) ? [normalize_combat_roll(parsed[:roll], parsed[:mechanical_summary])] : []

        EvaluationResult.new(
          intention: intention,
          player_rolls: rolls,
          consequences: Array(parsed[:consequences]).map(&:to_s).reject(&:blank?),
          mechanical_summary: parsed[:mechanical_summary].to_s.presence || '(no mechanical summary)'
        )
      end

      def needs_roll?(parsed)
        parsed[:needs_roll] == true && parsed[:roll].is_a?(Hash)
      end

      def normalize_combat_roll(raw, mechanical_summary)
        raw = raw.deep_symbolize_keys
        case raw[:type].to_s
        when 'attack_roll', 'saving_throw' then resolve_combat_roll(raw)
        else                                    normalize_skill_roll(raw, mechanical_summary)
        end
      end

      def resolve_combat_roll(raw)
        DungeonMaster::Steps::Phases::CombatMechanicResolution
          .send(:normalize_player_roll, raw, 0, context: combat_resolution_context)
          .deep_symbolize_keys
          .merge(rule_slug: raw[:rule_slug])
          .compact
      rescue DungeonMaster::CombatMechanicResolutionError => e
        @log&.play_log!(
          'combat_mech_eval_resolution_error',
          "CombatRollRequest: #{e.message}",
          parsed_response: { raw: raw }
        )
        {
          type: raw[:type],
          description: raw[:description].presence || '(combat roll)',
          rule_slug: raw[:rule_slug], dc: nil,
          error: e.message
        }.compact
      end

      def normalize_skill_roll(raw, mechanical_summary)
        {
          type: raw[:type].presence || 'skill_check',
          skill: raw[:skill],
          save: raw[:save],
          dc: raw[:dc],
          description: raw[:description].presence || mechanical_summary.to_s.presence || '(no description)',
          rule_slug: raw[:rule_slug],
          take_10_eligible: raw[:take_10_eligible] == true,
          take_20_eligible: raw[:take_20_eligible] == true,
          situational_modifiers: DungeonMaster::Rolls::SituationalModifiers.normalize(raw[:situational_modifiers])
        }.compact
      end

      def combat_resolution_context
        combat_ctx = @adventure.combat_context.is_a?(Hash) ? @adventure.combat_context : {}
        DungeonMaster::Steps::Phases::CombatMechanicResolution::CombatResolutionContext.new(
          combat_ctx: combat_ctx,
          adventure: @adventure,
          sheet: @sheet,
          lookup_context: DungeonMaster::WorldTurn::ParticipantLookup::LookupContext.new(
            combat_ctx: combat_ctx, player_sheet: @sheet, adventure: @adventure
          )
        )
      end

      def log_combat_roll_request_to_loop(result)
        return unless @loop

        rolls_desc = describe_player_rolls(result.player_rolls)

        @loop.batch_update!(
          new_data: { 'combat_roll_request' => true },
          new_status: 'resolving',
          timeline_entry: combat_roll_request_timeline_entry(rolls_desc)
        )
      end

      def describe_player_rolls(rolls)
        rolls.map { |r| "#{r[:skill] || r[:type]} DC #{r[:dc] || '?'}" }.join(', ')
      end

      def combat_roll_request_timeline_entry(rolls_desc)
        CombatRollRequest::TimelineEntry.new(rolls_desc: rolls_desc).to_h
      end
    end
  end
end
