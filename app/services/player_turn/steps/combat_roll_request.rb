# frozen_string_literal: true

module PlayerTurn
  module Steps
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
        system_prompt = Ai::PromptRenderer.render('combat_roll_request', combat_roll_request_context: ctx)
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
        target_id = combat_validated_target_id(parsed[:target_actor_sheet_id])
        rolls = needs_roll?(parsed) ? [normalize_combat_roll(parsed[:roll], parsed[:mechanical_summary])] : []
        apply_combat_opposed_dc!(rolls, target_id)

        EvaluationResult.new(
          intention: intention,
          target_actor_sheet_id: target_id,
          player_rolls: rolls,
          consequences: Array(parsed[:consequences]).map(&:to_s).reject(&:blank?),
          mechanical_summary: parsed[:mechanical_summary].to_s.presence || '(no mechanical summary)'
        )
      end

      def combat_validated_target_id(raw)
        return nil if raw.nil? || raw == ''

        id = Integer(raw, exception: false)
        return nil unless id&.positive?

        valid_ids = combat_participant_ids
        return id if valid_ids.empty?

        return id if valid_ids.include?(id)

        @log&.play_log!(
          'combat_roll_request_unknown_target',
          "CombatRollRequest: target_actor_sheet_id=#{id} not in active combat (valid=#{valid_ids.inspect})",
          parsed_response: UnknownTargetEvent.new(requested_id: id, valid_ids: valid_ids).to_h
        )
        nil
      end

      def combat_participant_ids
        combat_ctx = @adventure.combat_context.is_a?(Hash) ? @adventure.combat_context : {}
        Array(combat_ctx['participants']).filter_map do |p|
          row = p.is_a?(Hash) ? p.deep_stringify_keys : {}
          next nil unless row['type'].to_s == 'npc'

          Integer(row['actor_sheet_id'], exception: false)
        end.compact
      end

      def apply_combat_opposed_dc!(rolls, target_id)
        return if rolls.empty? || target_id.nil?

        target_sheet = @adventure.adventure_actor_sheets.find_by(id: target_id)
        return unless target_sheet

        rolls.each do |roll|
          next unless roll[:type].to_s == 'skill_check'

          roll[:dc] = Combat::OpposedRollResolution.resolve_dc(
            roll: roll, target_sheet: target_sheet, log: @log
          )
        end
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
        PlayerTurn::Steps::Phases::CombatMechanicResolution
          .send(:normalize_player_roll, raw, 0, context: combat_resolution_context)
          .deep_symbolize_keys
          .merge(rule_slug: raw[:rule_slug])
          .compact
      rescue Combat::MechanicResolutionError => e
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
          situational_modifiers: PlayerTurn::Rolls::SituationalModifiers.normalize(raw[:situational_modifiers])
        }.compact
      end

      def combat_resolution_context
        combat_ctx = @adventure.combat_context.is_a?(Hash) ? @adventure.combat_context : {}
        PlayerTurn::Steps::Phases::CombatMechanicResolution::CombatResolutionContext.new(
          combat_ctx: combat_ctx,
          adventure: @adventure,
          sheet: @sheet,
          lookup_context: Combat::WorldTurn::ParticipantLookup::LookupContext.new(
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
