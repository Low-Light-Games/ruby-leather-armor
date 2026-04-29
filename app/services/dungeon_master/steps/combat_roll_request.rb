# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step: CombatRollRequest — single-call replacement for the
    # legacy beacon → mechanical_evaluation → roll_qualifier chain on
    # combat-active free-text turns. Mirrors `Steps::RollRequest` but
    # carries combat-aware context (attack options, action economy,
    # threats, battlefield) so the model can pick a roll that actually
    # fits the tactical state.
    #
    # Pre-call code:
    #   * Pulls legal attack options from
    #     `DungeonMaster::Combat::AttackOptionBuilder`.
    #   * Pulls threats / flanking facts from `Combat::Positions` +
    #     `Combat::Rules`.
    #   * RAG-retrieves combat-biased rules via `Rules::Lookup` and
    #     scene beats via `Lore::FactsLookup`.
    #
    # The AI call:
    #   * Receives attack_options / threats / battlefield text but NO
    #     character sheet — DCs and bonuses resolve post-call from the
    #     sheet (mirroring the existing combat_mechanic invariant).
    #   * Output: same flat JSON as the out-of-combat RollRequest, but
    #     `roll.type` may be `attack_roll | saving_throw | skill_check`,
    #     and combat rolls emit `attack_option_id` + `target` instead of
    #     a DC.
    #
    # Post-call code:
    #   * `CombatRollRequest::Adapter` translates the flat JSON into
    #     `[intent, evaluations]` matching `ParallelEvaluation`,
    #     routing combat rolls through `CombatMechanicResolution` for
    #     deterministic DC computation.
    #   * `Rolls::PlayerRolls.deduplicate_rolls!` and
    #     `compute_take_values` still run.
    #
    # Routing: `AdventureLoopResolution#run_evaluation_phase` selects
    # this step when `combat_active?` AND
    # `DmConfig#combat_roll_request_mode?`. The legacy
    # `Steps::ParallelEvaluation` chain stays the default until
    # staging soak validates this path.
    module CombatRollRequest
      include Phases::RollQualifierPhase

      RULES_TOP_K = 4
      BEATS_TOP_K = 6
      DEFAULT_PROMPT_PROGRESS = 'Adjudicating your move...'

      private

      def run_combat_roll_request(intention)
        broadcast_progress(DEFAULT_PROMPT_PROGRESS)

        ctx = build_combat_roll_request_context(intention)
        prompt_summary = "CombatRollRequest: \"#{@log.truncate(intention)}\""
        system_prompt = PromptRenderer.render('combat_roll_request', combat_roll_request_context: ctx)
        request_body = { system_prompt: system_prompt, user_message: intention }

        parsed = timed_ai_call('combat_roll_request', prompt_summary, request_body) do
          raw = @ai.chat(
            system_prompt: system_prompt,
            user_message: intention,
            max_tokens: @config.token_budget_for('combat_roll_request'),
            step_name: 'combat_roll_request',
            model: @config.model_for('combat_roll_request'),
            reasoning_effort: @config.reasoning_effort_for('combat_roll_request')
          )
          [raw, @ai.parse_json(raw)]
        end

        intent, evaluations = CombatRollRequest::Adapter.call(
          parsed: parsed, intention: intention, adventure: @adventure, sheet: @sheet, log: @log
        )

        log_combat_roll_request_to_loop(intent, evaluations)
        evaluations = evaluations.map { |e| compute_take_values(e) }
        [intent, evaluations]
      end

      def build_combat_roll_request_context(intention)
        beats = retrieve_beats_for_combat_roll_request(intention)
        rules = retrieve_rules_for_combat_roll_request(intention)
        combat_ctx = @adventure.combat_context.is_a?(Hash) ? @adventure.combat_context : {}

        CombatRollRequest::Context.new(
          intent: intention,
          retrieval: { recent_beats: beats, relevant_rules: rules },
          combat: build_combat_facts(combat_ctx),
          state: { round: combat_ctx['round'], current_turn: combat_ctx['current_turn'] }
        )
      end

      def build_combat_facts(combat_ctx)
        {
          attack_options: DungeonMaster::Combat::AttackOptionBuilder.call(sheet: @sheet, adventure: @adventure),
          action_economy: combat_ctx['action_economy'] || {},
          threats: build_threats_for_player,
          battlefield_summary: DungeonMaster::Battlefield::PromptSerializer.slice_for_adventure(@adventure)
        }
      end

      def build_threats_for_player
        player_pos = Combat::Positions.player_position(@adventure)
        return [] unless player_pos&.coordinates_present?

        others = Combat::Positions.for_adventure(@adventure)
                                  .reject { |p| p.token_id == Combat::Positions::PLAYER_TOKEN_ID }

        threats = Combat::Rules.aoo_threats_against(mover: player_pos, mover_from: player_pos, others: others)
        threats.map { |threat| CombatRollRequest::ThreatSummary.new(threat: threat, player_pos: player_pos).to_h }
      end

      def retrieve_beats_for_combat_roll_request(intention)
        return [] unless defined?(DungeonMaster::Lore::FactsLookup)

        DungeonMaster::Lore::FactsLookup.call(
          adventure: @adventure, ai: @ai, log: @log,
          query_text: intention, limit: BEATS_TOP_K
        )
      end

      def retrieve_rules_for_combat_roll_request(intention)
        DungeonMaster::Rules::Lookup.call(
          ai: @ai, log: @log,
          query_text: combat_query(intention), limit: RULES_TOP_K
        )
      end

      def combat_query(intention)
        "combat: #{intention}"
      end

      def log_combat_roll_request_to_loop(intent, evaluations)
        return unless @loop

        affected = intent[:affected_contexts]
        rolls_desc = describe_player_rolls(evaluations)

        @loop.batch_update!(
          new_data: { 'affected_contexts' => affected, 'combat_roll_request' => true },
          new_status: 'resolving',
          timeline_entry: combat_roll_request_timeline_entry(affected, rolls_desc)
        )
      end

      def describe_player_rolls(evaluations)
        evaluations.flat_map { |e| e[:player_rolls] }
                   .map { |r| "#{r[:skill] || r[:type]} DC #{r[:dc] || '?'} (#{r[:domain]})" }
                   .join(', ')
      end

      def combat_roll_request_timeline_entry(affected, rolls_desc)
        CombatRollRequest::TimelineEntry.new(affected: affected, rolls_desc: rolls_desc).to_h
      end
    end
  end
end
