# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step: RollRequest — single-call replacement for the
    # beacon → mechanical_evaluation → roll_qualifier chain. Decides
    # whether the player's intent needs a die roll and emits one roll
    # spec (or "no roll") plus the cross-cutting signals downstream code
    # consumes from the legacy chain.
    #
    # Pre-call code:
    #   * Embeds the intent once and uses that vector both for rules
    #     retrieval (`Rules::Lookup`) and beats retrieval (`Lore::FactsLookup`)
    #     when both share the same embedding model. Beats retrieval is
    #     authoritative scene memory; rules retrieval is the RAG'd
    #     replacement for the legacy rules-manifest dump.
    #
    # The AI call:
    #   * Carries no character block (skill modifiers resolved post-call
    #     by code from the sheet via `compute_take_values`).
    #   * Carries no per-domain micro-contexts and no domain partials.
    #   * Carries the top-K rules and the top-K beats — nothing else.
    #
    # Post-call code:
    #   * `RollRequest::Adapter` translates the flat JSON into the
    #     `[intent, evaluations]` tuple `Steps::ParallelEvaluation`
    #     historically returned, so the rest of `AdventureLoopResolution`
    #     is unchanged.
    #   * `Rolls::PlayerRolls.deduplicate_rolls!` and
    #     `compute_take_values` still run on the merged result, identical
    #     to the legacy chain.
    #
    # Combat-active turns DO NOT reach this step — `AdventureLoopResolution`
    # routes through `Steps::ParallelEvaluation` unconditionally when
    # `combat_active?` so the Combat GM path stays bit-for-bit unchanged.
    module RollRequest
      include Phases::RollQualifierPhase

      RULES_TOP_K = 4
      BEATS_TOP_K = 6

      private

      def run_roll_request(intention)
        broadcast_progress('Reading the situation...')

        beats = retrieve_beats_for_roll_request(intention)
        rules = retrieve_rules_for_roll_request(intention)

        ctx = RollRequest::Context.new(
          intent: intention,
          recent_beats: beats,
          relevant_rules: rules
        )

        prompt_summary = "RollRequest: \"#{@log.truncate(intention)}\""
        system_prompt  = PromptRenderer.render('roll_request',
                                               roll_request_context: ctx,
                                               response_schema: PromptRenderer.load_schema('roll_request'))
        request_body   = { system_prompt: system_prompt, user_message: intention }

        parsed = timed_ai_call('roll_request', prompt_summary, request_body) do
          raw = @ai.chat(
            system_prompt: system_prompt,
            user_message: intention,
            max_tokens: @config.token_budget_for('roll_request'),
            step_name: 'roll_request',
            model: @config.model_for('roll_request')
          )
          [raw, @ai.parse_json(raw)]
        end

        intent, evaluations = RollRequest::Adapter.call(parsed: parsed, intention: intention)

        log_roll_request_to_loop(intent, evaluations)

        evaluations = evaluations.map { |e| compute_take_values(e) }
        [intent, evaluations]
      end

      def retrieve_beats_for_roll_request(intention)
        return [] unless defined?(DungeonMaster::Lore::FactsLookup)

        DungeonMaster::Lore::FactsLookup.call(
          adventure: @adventure,
          ai: @ai,
          log: @log,
          query_text: intention,
          limit: BEATS_TOP_K
        )
      end

      def retrieve_rules_for_roll_request(intention)
        DungeonMaster::Rules::Lookup.call(
          ai: @ai,
          log: @log,
          query_text: intention,
          limit: RULES_TOP_K
        )
      end

      def log_roll_request_to_loop(intent, evaluations)
        return unless @loop

        affected   = intent[:affected_contexts]
        rolls_desc = evaluations.flat_map { |e| e[:player_rolls] }
                                .map { |r| "#{r[:skill] || r[:type]} DC #{r[:dc]} (#{r[:domain]})" }
                                .join(', ')

        @loop.batch_update!(
          new_data: { 'affected_contexts' => affected, 'roll_request' => true },
          new_status: 'resolving',
          timeline_entry: {
            'step' => 'roll_request',
            'summary' => [
              "Affected: #{affected.join(', ').presence || 'none'}",
              rolls_desc.presence || 'No rolls'
            ].join(' | '),
            'at' => Time.current.iso8601
          }
        )
      end
    end
  end
end
