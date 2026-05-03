# frozen_string_literal: true

module DungeonMaster
  module Steps
    # Pipeline Step: RollRequest — single AI call that decides whether the
    # player's intent needs a die roll. Out-of-combat only;
    # CombatRollRequest covers combat-active free-text.
    #
    # Pre-call: embeds the intent once for both rules retrieval
    # ({Rules::Lookup}) and beats retrieval ({Lore::FactsLookup}).
    #
    # The AI call carries no character block, no per-domain micro-contexts,
    # and no domain partials — only the top-K rules and the top-K beats.
    # Skill modifiers / DCs are resolved post-call by code from the sheet.
    #
    # Returns an {EvaluationResult} built directly from the parsed JSON.
    module RollRequest
      RULES_TOP_K = 4
      BEATS_TOP_K = 6

      DOMAIN_PRIORITY = %w[combat buff social traversal exploration rest inventory].freeze

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
                                               roll_request_context: ctx)
        request_body   = { system_prompt: system_prompt, user_message: intention }

        parsed = timed_ai_call('roll_request', prompt_summary, request_body) do
          raw = @ai.chat(
            system_prompt: system_prompt,
            user_message: intention,
            max_tokens: @config.token_budget_for('roll_request'),
            step_name: 'roll_request',
            model: @config.model_for('roll_request'),
            reasoning_effort: @config.reasoning_effort_for('roll_request')
          )
          [raw, @ai.parse_json(raw)]
        end

        result = build_evaluation_result(parsed: parsed, intention: intention)

        warn_on_invented_rule_slug!(parsed, rules)
        log_roll_request_to_loop(result)

        Rolls::PlayerRolls.compute_take_values!(result.player_rolls, sheet: @sheet)
        result
      end

      def build_evaluation_result(parsed:, intention:)
        parsed = (parsed || {}).deep_symbolize_keys
        affected = ordered_affected_domains(parsed[:affected_domains])
        primary = affected.first
        rolls = if needs_roll?(parsed)
                  [normalize_roll(parsed[:roll],
                                  primary_domain: primary,
                                  mechanical_summary: parsed[:mechanical_summary])]
                else
                  []
                end

        EvaluationResult.new(
          intention: intention,
          affected_contexts: affected,
          destination: parsed[:destination],
          combat_transition: parsed[:transition],
          combat_combatants: normalized_combatants(parsed[:combatants]),
          player_rolls: rolls,
          consequences: DungeonMaster::Rolls::Consequences.normalize(parsed[:consequences]),
          mechanical_summary: parsed[:mechanical_summary].to_s.presence || '(no mechanical summary)'
        )
      end

      def needs_roll?(parsed)
        parsed[:needs_roll] == true && parsed[:roll].is_a?(Hash)
      end

      def normalize_roll(raw, primary_domain:, mechanical_summary:)
        raw = raw.deep_symbolize_keys
        {
          type: raw[:type].presence || 'skill_check',
          skill: raw[:skill],
          save: raw[:save],
          dc: raw[:dc],
          description: raw[:description].presence || mechanical_summary.to_s.presence || '(no description)',
          domain: primary_domain,
          rule_slug: raw[:rule_slug],
          take_10_eligible: raw[:take_10_eligible] == true,
          take_20_eligible: raw[:take_20_eligible] == true,
          situational_modifiers: DungeonMaster::Rolls::SituationalModifiers.normalize(raw[:situational_modifiers])
        }.compact
      end

      def ordered_affected_domains(raw)
        domains = Array(raw).map { |d| d.to_s.downcase }.reject(&:blank?).uniq
        DOMAIN_PRIORITY.select { |d| domains.include?(d) } + (domains - DOMAIN_PRIORITY)
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

      # Observability only — write a play_log row when the model emits a
      # rule_slug that wasn't in the retrieved set, so we can measure how
      # often the AI ignores its own RAG context.
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

      def retrieve_beats_for_roll_request(intention)
        DungeonMaster::SceneFacts::ForResolution.call(
          adventure: @adventure,
          intent_text: intention,
          ai: @ai,
          log: @log,
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

      def log_roll_request_to_loop(result)
        return unless @loop

        rolls_desc = result.player_rolls
                           .map { |r| "#{r[:skill] || r[:type]} DC #{r[:dc]} (#{r[:domain]})" }
                           .join(', ')

        @loop.batch_update!(
          new_data: { 'affected_contexts' => result.affected_contexts, 'roll_request' => true },
          new_status: 'resolving',
          timeline_entry: {
            'step' => 'roll_request',
            'summary' => [
              "Affected: #{result.affected_contexts.join(', ').presence || 'none'}",
              rolls_desc.presence || 'No rolls'
            ].join(' | '),
            'at' => Time.current.iso8601
          }
        )
      end
    end
  end
end
